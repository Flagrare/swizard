import Foundation
@testable import DBIProtocol

/// Test double for DBISessionDelegate that records all events.
final class MockSessionDelegate: DBISessionDelegate, @unchecked Sendable {
    struct LogEvent: Equatable {
        let message: String
        let level: LogLevel
    }

    struct FileChunkEvent: Equatable {
        let fileName: String
        let bytesInChunk: UInt32
        let totalOffset: UInt64
    }

    private(set) var logEvents: [LogEvent] = []
    private(set) var fileChunkEvents: [FileChunkEvent] = []
    private(set) var exitReceived = false

    /// Convenience: just the message strings (for backward-compatible assertions).
    var logMessages: [String] { logEvents.map(\.message) }

    func sessionDidLog(_ message: String, level: LogLevel) {
        logEvents.append(LogEvent(message: message, level: level))
    }

    func sessionDidSendFileChunk(fileName: String, bytesInChunk: UInt32, totalOffset: UInt64) {
        fileChunkEvents.append(FileChunkEvent(fileName: fileName, bytesInChunk: bytesInChunk, totalOffset: totalOffset))
    }

    func sessionDidReceiveExit() {
        exitReceived = true
    }
}
