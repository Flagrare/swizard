import Foundation
@testable import DBIProtocol

/// Test double for DBISessionDelegate that records all events.
final class MockSessionDelegate: DBISessionDelegate, @unchecked Sendable {
    struct FileChunkEvent: Equatable {
        let fileName: String
        let bytesInChunk: UInt32
        let totalOffset: UInt64
    }

    private(set) var logMessages: [String] = []
    private(set) var fileChunkEvents: [FileChunkEvent] = []
    private(set) var exitReceived = false

    func sessionDidLog(_ message: String) {
        logMessages.append(message)
    }

    func sessionDidSendFileChunk(fileName: String, bytesInChunk: UInt32, totalOffset: UInt64) {
        fileChunkEvents.append(FileChunkEvent(fileName: fileName, bytesInChunk: bytesInChunk, totalOffset: totalOffset))
    }

    func sessionDidReceiveExit() {
        exitReceived = true
    }
}
