import XCTest
@testable import USBTransport

final class RetryPolicyTests: XCTestCase {

    func testDefaultPolicyHasThreeAttempts() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
    }

    func testNonePolicyHasOneAttempt() {
        let policy = RetryPolicy.none
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    func testExponentialBackoffDelays() {
        let policy = RetryPolicy(maxAttempts: 5, baseDelay: 0.1, maxDelay: 2.0)

        XCTAssertEqual(policy.delay(forAttempt: 0), 0.1, accuracy: 0.001)  // 0.1 * 2^0
        XCTAssertEqual(policy.delay(forAttempt: 1), 0.2, accuracy: 0.001)  // 0.1 * 2^1
        XCTAssertEqual(policy.delay(forAttempt: 2), 0.4, accuracy: 0.001)  // 0.1 * 2^2
        XCTAssertEqual(policy.delay(forAttempt: 3), 0.8, accuracy: 0.001)  // 0.1 * 2^3
    }

    func testDelayClampedToMax() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 1.0, maxDelay: 2.0)

        // 1.0 * 2^5 = 32.0, but clamped to 2.0
        XCTAssertEqual(policy.delay(forAttempt: 5), 2.0)
    }

    func testZeroBaseDelayAlwaysReturnsZero() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0)

        XCTAssertEqual(policy.delay(forAttempt: 0), 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0)
    }
}
