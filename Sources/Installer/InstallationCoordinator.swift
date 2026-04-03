import Foundation
import DBIProtocol
import USBTransport

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

    public private(set) var state: State = .idle
    public let progress = TransferProgress()
    public private(set) var logs: [LogEntry] = []

    private let transport: any TransportProtocol
    private let fileServer = FileServer()
    private let session: DBISession
    private let sessionDelegateAdapter: SessionDelegateAdapter
    private let reconnectPolicy: ReconnectPolicy
    private var installTask: Task<Void, Never>?

    public init(
        transport: (any TransportProtocol)? = nil,
        reconnectPolicy: ReconnectPolicy = .default
    ) {
        self.transport = transport ?? USBTransport().withRetry()
        self.reconnectPolicy = reconnectPolicy
        let adapter = SessionDelegateAdapter()
        self.sessionDelegateAdapter = adapter
        self.session = DBISession()
        self.session.delegate = adapter
    }

    public func queueFiles(_ urls: [URL]) {
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
        sessionDelegateAdapter.onFileChunk = { [weak self] fileName, _, totalOffset in
            Task { @MainActor in self?.progress.updateProgress(fileName: fileName, transferredBytes: totalOffset) }
        }

        installTask = Task { [weak self] in
            await self?.runInstallation()
        }
    }

    public func cancel() {
        installTask?.cancel()
        installTask = nil
        log("Cancellation requested")
    }

    public func reset() {
        cancel()
        state = .idle
        progress.clear()
        logs.removeAll()
    }

    // MARK: - Private

    private func runInstallation() async {
        state = .connecting
        log("Connecting to Switch...", level: .info)

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
        installTask = nil
    }

    private func runSessionWithReconnect() async throws {
        var reconnectAttempts = 0

        while true {
            do {
                state = .transferring
                try await session.run(transport: transport, fileServer: fileServer)
                return // Session completed normally (EXIT received)
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

    func log(_ message: String, level: LogLevel = .info) {
        logs.append(LogEntry(message: message, level: level))
    }
}

// MARK: - LogEntry

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let message: String
    public let level: LogLevel

    public init(message: String, level: LogLevel = .info) {
        self.message = message
        self.level = level
    }
}

// MARK: - SessionDelegateAdapter

final class SessionDelegateAdapter: DBISessionDelegate, @unchecked Sendable {
    var onLog: ((String, LogLevel) -> Void)?
    var onFileChunk: ((String, UInt32, UInt64) -> Void)?
    var onExit: (() -> Void)?

    func sessionDidLog(_ message: String, level: LogLevel) {
        onLog?(message, level)
    }

    func sessionDidSendFileChunk(fileName: String, bytesInChunk: UInt32, totalOffset: UInt64) {
        onFileChunk?(fileName, bytesInChunk, totalOffset)
    }

    func sessionDidReceiveExit() {
        onExit?()
    }
}
