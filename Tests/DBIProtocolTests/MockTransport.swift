import Foundation
@testable import DBIProtocol

/// Test double that scripts USB conversations.
/// Plays back queued reads (data or errors) and records all writes for assertion.
final class MockTransport: TransportProtocol, @unchecked Sendable {
    private var readQueue: [Result<Data, any Error>] = []
    private(set) var writtenData: [Data] = []
    private(set) var isConnected = false

    /// When true, an exhausted read queue simulates an idle Switch (endless timeouts).
    var idleForeverWhenExhausted = false

    /// Queue data that will be returned by successive `read` calls.
    func queueRead(_ data: Data) {
        readQueue.append(.success(data))
    }

    /// Queue a pre-built DBI header for reading.
    func queueReadHeader(_ header: DBIHeader) {
        queueRead(header.encoded())
    }

    /// Queue `count` read timeouts, simulating a Switch that is idle (e.g. user browsing files).
    func queueReadTimeouts(_ count: Int) {
        readQueue.append(contentsOf: Array(repeating: .failure(MockTimeoutError()), count: count))
    }

    func connect() async throws {
        isConnected = true
    }

    func disconnect() async throws {
        isConnected = false
    }

    func read(maxLength: Int) async throws -> Data {
        guard !readQueue.isEmpty else {
            if idleForeverWhenExhausted {
                await Task.yield()
                throw MockTimeoutError()
            }
            throw MockTransportError.noMoreData
        }
        return try readQueue.removeFirst().get()
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

struct MockTimeoutError: TransportError {
    var isTimeout: Bool { true }
}
