import Foundation
import DBIProtocol

/// Bridges DBISessionDelegate (called from background) to MainActor coordinator.
/// Uses closures to avoid direct cross-actor references.
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
