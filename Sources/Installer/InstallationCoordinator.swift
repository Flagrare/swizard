import Foundation
import DBIProtocol
import USBTransport
import MTPTransport
import NativeMTPTransport
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
    public var mtpInstallDestination: MTPInstallDestination?
    public let progress = TransferProgress()
    public private(set) var logs: [LogEntry] = []

    private let transport: any TransportProtocol
    private let mtpDevice: any MTPDeviceProtocol
    private let mtpSession: any MTPSessionProtocol
    private let fileServer = FileServer()
    private let session: DBISession
    private let sessionDelegateAdapter: SessionDelegateAdapter
    private let reconnectPolicy: ReconnectPolicy
    private let ftpClient: any FTPUploadClientProtocol
    private var installTask: Task<Void, Never>?
    private var queuedURLs: [URL] = []
    public var ftpAddress: String = ""
    public private(set) var networkInfo: String?

    public init(
        transport: (any TransportProtocol)? = nil,
        mtpDevice: (any MTPDeviceProtocol)? = nil,
        mtpSession: (any MTPSessionProtocol)? = nil,
        ftpClient: (any FTPUploadClientProtocol)? = nil,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.transport = transport ?? USBTransport().withRetry()
        self.mtpDevice = mtpDevice ?? MTPDevice()
        self.mtpSession = mtpSession ?? PrivilegedMTPSession()
        self.ftpClient = ftpClient ?? FTPUploadClient()
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
        // FTP client uses curl Process which is killed when task is cancelled
        networkInfo = nil
        log("Cancellation requested")
    }

    public func reset() {
        cancel()
        // FTP client uses curl Process which is killed when task is cancelled
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
        log("MTP requires admin privileges to claim USB from macOS.", level: .warning)

        let files = queuedURLs.map { url -> PrivilegedMTPSession.FileToInstall in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return PrivilegedMTPSession.FileToInstall(path: url.path, name: url.lastPathComponent, size: size)
        }

        let mtpSess = mtpSession

        do {
            try await mtpSess.install(
                files: files,
                targetStorageID: mtpInstallDestination?.storageID,
                onProgress: { [weak self] fileName, sent, total in
                    Task { @MainActor in
                        if self?.state == .connecting { self?.state = .transferring }
                        self?.progress.updateProgress(fileName: fileName, transferredBytes: sent)
                    }
                },
                onLog: { [weak self] (message: String) in
                    Task { @MainActor in
                        self?.log("[MTP] \(message)", level: .debug)
                    }
                }
            )

            state = .complete
            log("Installation complete!", level: .info)
        } catch is CancellationError {
            state = .idle
            log("Installation cancelled", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("Error: \(error.localizedDescription)", level: .error)
        }
    }

    // MARK: - Network Path

    private func runNetworkInstallation() async {
        state = .connecting

        guard let connection = FTPConnectionInfo.parse(ftpAddress) else {
            state = .error("Invalid FTP address. Enter Switch IP:port (e.g., 192.168.0.96:5000)")
            log("Invalid FTP address: \(ftpAddress)", level: .error)
            return
        }

        log("Connecting to Switch FTP at \(connection.displayString)...", level: .info)

        do {
            state = .transferring

            for url in queuedURLs {
                let fileName = url.lastPathComponent
                let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0

                try await ftpClient.upload(
                    file: url,
                    to: connection,
                    onProgress: { [weak self] percentage in
                        Task { @MainActor in
                            let bytes = UInt64(Double(fileSize) * percentage / 100.0)
                            self?.progress.updateProgress(fileName: fileName, transferredBytes: bytes)
                        }
                    },
                    onLog: { [weak self] (message: String) in
                        Task { @MainActor in
                            self?.log("[FTP] \(message)", level: .debug)
                        }
                    }
                )

                log("\(fileName) installed via FTP", level: .info)
            }

            state = .complete
            log("All files installed via FTP!", level: .info)
        } catch is CancellationError {
            state = .idle
            log("FTP transfer cancelled", level: .warning)
        } catch {
            state = .error(error.localizedDescription)
            log("FTP error: \(error.localizedDescription)", level: .error)
        }
    }

    public func log(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(message: message, level: level))
    }
}
