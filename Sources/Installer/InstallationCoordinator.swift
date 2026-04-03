import Foundation
import DBIProtocol
import USBTransport

/// Mediator: orchestrates USB connection, DBI protocol, and file serving.
/// MainActor-isolated to safely drive @Observable state for SwiftUI.
@Observable
@MainActor
public final class InstallationCoordinator {
    public enum State: Sendable {
        case idle
        case connecting
        case connected
        case transferring
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
    private var installTask: Task<Void, Never>?

    public init(transport: (any TransportProtocol)? = nil) {
        self.transport = transport ?? USBTransport()
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

        // Wire delegate callbacks to self (MainActor)
        sessionDelegateAdapter.onLog = { [weak self] message in
            Task { @MainActor in self?.log(message) }
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
        log("Connecting to Switch...")

        do {
            try await transport.connect()
            state = .connected
            log("Connected to Switch")

            state = .transferring

            try await session.run(transport: transport, fileServer: fileServer)

            state = .complete
            log("Installation complete!")
        } catch is CancellationError {
            state = .idle
            log("Installation cancelled")
        } catch {
            state = .error(error.localizedDescription)
            log("Error: \(error.localizedDescription)")
        }

        try? await transport.disconnect()
        installTask = nil
    }

    func log(_ message: String) {
        logs.append(LogEntry(message: message))
    }
}

// MARK: - LogEntry

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let message: String
}

// MARK: - SessionDelegateAdapter

/// Bridges DBISessionDelegate (called from background) to MainActor coordinator.
/// Uses closures to avoid direct cross-actor references.
final class SessionDelegateAdapter: DBISessionDelegate, @unchecked Sendable {
    var onLog: ((String) -> Void)?
    var onFileChunk: ((String, UInt32, UInt64) -> Void)?
    var onExit: (() -> Void)?

    func sessionDidLog(_ message: String) {
        onLog?(message)
    }

    func sessionDidSendFileChunk(fileName: String, bytesInChunk: UInt32, totalOffset: UInt64) {
        onFileChunk?(fileName, bytesInChunk, totalOffset)
    }

    func sessionDidReceiveExit() {
        onExit?()
    }
}
