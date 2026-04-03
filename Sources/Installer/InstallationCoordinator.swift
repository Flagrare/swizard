import Foundation
import DBIProtocol
import USBTransport

/// Mediator: orchestrates USB connection, DBI protocol, and file serving.
@Observable
public final class InstallationCoordinator: @unchecked Sendable {
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
    private let session = DBISession()
    private var installTask: Task<Void, Never>?

    public init(transport: (any TransportProtocol)? = nil) {
        self.transport = transport ?? USBTransport()
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

        installTask = Task { [weak self] in
            await self?.runInstallation()
        }
    }

    public func cancel() {
        installTask?.cancel()
        installTask = nil
        state = .idle
        log("Installation cancelled")
    }

    public func reset() {
        cancel()
        state = .idle
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
            log("Starting DBI session...")

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
    }

    func log(_ message: String) {
        let entry = LogEntry(message: message)
        logs.append(entry)
    }
}

public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let message: String
}
