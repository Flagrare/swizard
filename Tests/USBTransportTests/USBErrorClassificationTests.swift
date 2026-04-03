import XCTest
@testable import USBTransport

final class USBErrorClassificationTests: XCTestCase {

    // MARK: - isRetryable

    func testTimeoutIsRetryable() {
        XCTAssertTrue(USBError.timeout.isRetryable)
    }

    func testPipeErrorIsRetryable() {
        // LIBUSB_ERROR_PIPE = -9
        XCTAssertTrue(USBError.transferFailed(-9).isRetryable)
    }

    func testOverflowErrorIsRetryable() {
        // LIBUSB_ERROR_OVERFLOW = -8
        XCTAssertTrue(USBError.transferFailed(-8).isRetryable)
    }

    func testDisconnectedIsNotRetryable() {
        XCTAssertFalse(USBError.disconnected.isRetryable)
    }

    func testDeviceNotFoundIsNotRetryable() {
        XCTAssertFalse(USBError.deviceNotFound.isRetryable)
    }

    func testNotConnectedIsNotRetryable() {
        XCTAssertFalse(USBError.notConnected.isRetryable)
    }

    func testClaimFailedIsNotRetryable() {
        XCTAssertFalse(USBError.claimFailed(-1).isRetryable)
    }

    func testGenericTransferFailedIsNotRetryable() {
        // Random error code that isn't pipe/overflow/interrupted
        XCTAssertFalse(USBError.transferFailed(-99).isRetryable)
    }

    // MARK: - requiresStallRecovery

    func testPipeErrorRequiresStallRecovery() {
        XCTAssertTrue(USBError.transferFailed(-9).requiresStallRecovery)
    }

    func testTimeoutDoesNotRequireStallRecovery() {
        XCTAssertFalse(USBError.timeout.requiresStallRecovery)
    }

    func testDisconnectedDoesNotRequireStallRecovery() {
        XCTAssertFalse(USBError.disconnected.requiresStallRecovery)
    }
}
