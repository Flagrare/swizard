import Foundation
import DBIProtocol
import USBTransport
import MTPTransport
import NetworkTransport

/// Mediator: orchestrates USB connection, DBI protocol, and file serving.
/// MainActor-isolated to safely drive @Observable state for SwiftUI.
@Observable
@MainActor
public final class InstallationCoordinator {
    public enum State: Sendable, Equatable {
        case idle
        case connecting
        case connected
        case transferring
        case reconnecting(attempt: Int)
        case complete
        case error(String)
    }

    public enum TransportMode: String, Sendable, CaseIterable {
        case dbiBackend = "DBI Backend"
        case mtp = "MTP"
        case network = "Network"
    }

    public private(set) var state: State = .idle
    public var transportMode: TransportMode = .mtp
    public let progress = TransferProgress()
    public private(set) var logs: [LogEntry] = []

    private let transport: any TransportProtocol
    private let mtpDevice: any MTPDeviceProtocol
    private let fileServer = FileServer()
    private let session: DBISession
    private let sessionDelegateAdapter: SessionDelegateAdapter
    private let reconnectPolicy: ReconnectPolicy
    private let networkServer = NetworkInstallServer()
    private var installTask: Task<Void, Never>?
    private var queuedURLs: [URL] = []
    public private(set) var networkInfo: String?

    public init(
        transport: (any TransportProtocol)? = nil,
        mtpDevice: (any MTPDeviceProtocol)? = nil,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.transport = transport ?? USBTransport().withRetry()
        self.mtpDevice = mtpDevice ?? MTPDevice()
        self.reconnectPolicy = reconnectPolicy
        let adapter = SessionDelegateAdapter()
        self.sessionDelegateAdapter = adapter
        self.session = DBISession()
        self.session.delegate = adapter
    }

    public func queueFiles(_ urls: [URL]) {
        queuedURLs.append(contentsOf: urls)
        fileServer.register(files: urls)
        for url in urls {
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            progress.register(name: url.lastPathComponent, totalBytes: size)
        }
        log("Queued \(urls.count) file(s)")
    }

    public func startInstallation() {
        guard case .idle = state else { return }
        guard fileServer.fileCount > 0 else {
            log("No files queued")
            return
        }

        sessionDelegateAdapter.onLog = { [weak self] message, level in
            Task { @MainActor in self?.log(message, level: level) }
        }
        sessionDelegateAdapter.onFileChunk = { [weak self] fileName, bytesInChunk, _ in
            Task { @MainActor in
                self?.progress.applyChunk(fileName: fileName, bytesInChunk: bytesInChunk)
            }
        }

        installTask = Task { [weak self] in
            await self?.runInstallation()
        }
    }

    public func cancel() {
        installTask?.cancel()
        installTask = nil
        networkServer.stop()
        networkInfo = nil
        log("Cancellation requested")
    }

    public func reset() {
        cancel()
        networkServer.stop()
        state = .idle
        progress.clear()
        logs.removeAll()
        queuedURLs.removeAll()
        networkInfo = nil
    }

    // MARK: - Private

    private func runInstallation() async {
        switch transportMode {
        case .dbiBackend:
            await runDBIBackendInstallation()
        case .mtp:
            await runMTPInstallation()
        case .network:
            await runNetworkInstallation()
        }
        installTask = nil
    }

    // MARK: - DBI Backend Path

    private func runDBIBackendInstallation() async {
        state = .connecting
        log("Connecting to Switch (DBI Backend)...", level: .info)

        do {
            try await transport.connect()
            state = .connected
            log("Connected to Switch", level: .info)

            try await runSessionWithReconnect()

            state = .complete
            log("Installation complete!", level: .info)
        } catch is CancellationError {
            state = .idle
            log("Installation cancelled", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("Error: \(error.localizedDescription)", level: .error)
        }

        try? await transport.disconnect()
    }

    private func runSessionWithReconnect() async throws {
        var reconnectAttempts = 0

        while true {
            do {
                state = .transferring
                try await session.run(transport: transport, fileServer: fileServer)
                return
            } catch let error as USBError where error == .disconnected {
                guard reconnectAttempts < reconnectPolicy.maxAttempts else {
                    throw error
                }

                reconnectAttempts += 1
                state = .reconnecting(attempt: reconnectAttempts)
                log("Connection lost. Reconnecting (\(reconnectAttempts)/\(reconnectPolicy.maxAttempts))...", level: .warning)

                try? await transport.disconnect()

                if reconnectPolicy.baseDelay > 0 {
                    try await Task.sleep(for: .seconds(reconnectPolicy.baseDelay))
                }

                try await transport.connect()
                log("Reconnected to Switch", level: .info)
            }
        }
    }

    // MARK: - MTP Path

    private func runMTPInstallation() async {
        state = .connecting
        log("Connecting to Switch (MTP)...", level: .info)

        let files = queuedURLs.map { url -> (String, String, UInt64) in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return (url.path, url.lastPathComponent, size)
        }

        let installer = MTPInstaller(device: mtpDevice)
        var attempts = 0
        let maxRetries = 3

        while true {
            do {
                try await installer.install(files: files) { [weak self] fileName, sent, total in
                    Task { @MainActor in
                        if self?.state == .connecting { self?.state = .transferring }
                        self?.progress.updateProgress(fileName: fileName, transferredBytes: sent)
                    }
                    return true
                }

                state = .complete
                log("Installation complete!", level: .info)
                return
            } catch is CancellationError {
                state = .idle
                log("Installation cancelled", level: .warning)
                return
            } catch let error as MTPError where error.isRetryable && attempts < maxRetries {
                attempts += 1
                log("MTP error, retrying (\(attempts)/\(maxRetries))...", level: .warning)
                try? await Task.sleep(for: .seconds(1))
            } catch {
                state = .error(error.localizedDescription)
                log("Error: \(error.localizedDescription)", level: .error)
                return
            }
        }
    }

    // MARK: - Network Path

    private func runNetworkInstallation() async {
        state = .connecting
        log("Starting HTTP server for network install...", level: .info)

        do {
            // Capture file names before entering @Sendable closure
            let fileNames = queuedURLs.map(\.lastPathComponent)
            let urlList = try networkServer.start(files: queuedURLs) { [weak self] fileIndex, bytesSent, _ in
                let fileName = fileIndex < fileNames.count ? fileNames[fileIndex] : "file \(fileIndex)"
                Task { @MainActor in
                    self?.progress.updateProgress(fileName: fileName, transferredBytes: bytesSent)
                }
            }

            let host = NetworkInstallServer.localIPAddress() ?? "localhost"
            networkInfo = "\(host):5000"
            state = .transferring
            log("HTTP server running at \(host):5000", level: .info)
            log("File URLs:\n\(urlList)", level: .debug)
            log("On your Switch: DBI → Run HTTP server → enter this URL", level: .info)

            // Keep server running until cancelled
            while !Task.isCancelled {
                try await Task.sleep(for: .seconds(1))
            }
        } catch is CancellationError {
            state = .idle
            log("Network server stopped", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("Error: \(error.localizedDescription)", level: .error)
        }

        networkServer.stop()
        networkInfo = nil
    }

    public func log(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(message: message, level: level))
    }
}
