import Foundation
@testable import DBIProtocol
@testable import USBTransport

/// Mock transport that fails a specified number of times before succeeding.
/// Used to test RetryableTransport's retry behavior.
final class FailableMockTransport: TransportProtocol, @unchecked Sendable {
    private let failureCount: Int
    private let failureError: any Error
    private var readAttempts = 0
    private var writeAttempts = 0
    private(set) var stallRecoveryCalls = 0

    let successData: Data

    init(failureCount: Int, failureError: any Error, successData: Data = Data([0x01, 0x02])) {
        self.failureCount = failureCount
        self.failureError = failureError
        self.successData = successData
    }

    func connect() async throws {}
    func disconnect() async throws {}

    func read(maxLength: Int) async throws -> Data {
        readAttempts += 1
        if readAttempts <= failureCount {
            throw failureError
        }
        return successData
    }

    func write(_ data: Data) async throws {
        writeAttempts += 1
        if writeAttempts <= failureCount {
            throw failureError
        }
    }

    var totalReadAttempts: Int { readAttempts }
    var totalWriteAttempts: Int { writeAttempts }
}
