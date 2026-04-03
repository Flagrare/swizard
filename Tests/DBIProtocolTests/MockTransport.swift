import Foundation
@testable import DBIProtocol

/// Test double that scripts USB conversations.
/// Plays back queued reads and records all writes for assertion.
final class MockTransport: TransportProtocol, @unchecked Sendable {
    private var readQueue: [Data] = []
    private(set) var writtenData: [Data] = []
    private(set) var isConnected = false

    /// Queue data that will be returned by successive `read` calls.
    func queueRead(_ data: Data) {
        readQueue.append(data)
    }

    /// Queue a pre-built DBI header for reading.
    func queueReadHeader(_ header: DBIHeader) {
        queueRead(header.encoded())
    }

    func connect() async throws {
        isConnected = true
    }

    func disconnect() async throws {
        isConnected = false
    }

    func read(maxLength: Int) async throws -> Data {
        guard !readQueue.isEmpty else {
            throw MockTransportError.noMoreData
        }
        return readQueue.removeFirst()
    }

    func write(_ data: Data) async throws {
        writtenData.append(data)
    }

    /// Decode a written header at a given index in the write log.
    func writtenHeader(at index: Int) throws -> DBIHeader {
        try DBIHeader(from: writtenData[index])
    }
}

enum MockTransportError: Error {
    case noMoreData
}
