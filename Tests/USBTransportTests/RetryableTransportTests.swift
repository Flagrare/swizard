import XCTest
@testable import USBTransport
@testable import DBIProtocol

final class RetryableTransportTests: XCTestCase {

    // MARK: - Read retry behavior

    func testReadRetriesOnTimeoutThenSucceeds() async throws {
        let inner = FailableMockTransport(failureCount: 2, failureError: USBError.timeout)
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0) // no delay for tests
        let transport = RetryableTransport(inner: inner, policy: policy)

        let data = try await transport.read(maxLength: 16)

        XCTAssertEqual(data, inner.successData)
        XCTAssertEqual(inner.totalReadAttempts, 3) // 2 failures + 1 success
    }

    func testReadDoesNotRetryOnFatalError() async {
        let inner = FailableMockTransport(failureCount: 1, failureError: USBError.disconnected)
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0)
        let transport = RetryableTransport(inner: inner, policy: policy)

        do {
            _ = try await transport.read(maxLength: 16)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(inner.totalReadAttempts, 1) // no retry
        }
    }

    func testReadThrowsAfterExhaustingRetries() async {
        let inner = FailableMockTransport(failureCount: 5, failureError: USBError.timeout)
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0)
        let transport = RetryableTransport(inner: inner, policy: policy)

        do {
            _ = try await transport.read(maxLength: 16)
            XCTFail("Should have thrown after max attempts")
        } catch let error as USBError {
            XCTAssertEqual(error, .timeout)
            XCTAssertEqual(inner.totalReadAttempts, 3)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Write retry behavior

    func testWriteRetriesOnTimeoutThenSucceeds() async throws {
        let inner = FailableMockTransport(failureCount: 1, failureError: USBError.timeout)
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0)
        let transport = RetryableTransport(inner: inner, policy: policy)

        try await transport.write(Data([0xAA]))

        XCTAssertEqual(inner.totalWriteAttempts, 2) // 1 failure + 1 success
    }

    // MARK: - Stall recovery

    func testStallRecoveryCalledOnPipeError() async throws {
        let inner = FailableMockTransport(
            failureCount: 1,
            failureError: USBError.transferFailed(-9) // PIPE
        )
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0)

        var stallRecoveryCalled = false
        let transport = RetryableTransport(inner: inner, policy: policy) {
            stallRecoveryCalled = true
        }

        _ = try await transport.read(maxLength: 16)

        XCTAssertTrue(stallRecoveryCalled)
    }

    func testStallRecoveryNotCalledOnTimeout() async throws {
        let inner = FailableMockTransport(failureCount: 1, failureError: USBError.timeout)
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0)

        var stallRecoveryCalled = false
        let transport = RetryableTransport(inner: inner, policy: policy) {
            stallRecoveryCalled = true
        }

        _ = try await transport.read(maxLength: 16)

        XCTAssertFalse(stallRecoveryCalled)
    }

    // MARK: - Pass-through

    func testConnectPassesThrough() async throws {
        let inner = FailableMockTransport(failureCount: 0, failureError: USBError.timeout)
        let transport = RetryableTransport(inner: inner, policy: .default)

        try await transport.connect()
        // No error means pass-through worked
    }

    func testDisconnectPassesThrough() async throws {
        let inner = FailableMockTransport(failureCount: 0, failureError: USBError.timeout)
        let transport = RetryableTransport(inner: inner, policy: .default)

        try await transport.disconnect()
    }

    // MARK: - No retry policy

    func testNonePolicyDoesNotRetry() async {
        let inner = FailableMockTransport(failureCount: 1, failureError: USBError.timeout)
        let transport = RetryableTransport(inner: inner, policy: .none)

        do {
            _ = try await transport.read(maxLength: 16)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(inner.totalReadAttempts, 1) // only 1 attempt
        }
    }
}
