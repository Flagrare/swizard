import Foundation

/// Policy Object: configures retry behavior for transient USB errors.
/// Pure value type — no side effects, testable in isolation.
public struct RetryPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval
    public let maxDelay: TimeInterval

    public init(maxAttempts: Int, baseDelay: TimeInterval, maxDelay: TimeInterval) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    /// Exponential backoff: baseDelay * 2^attempt, clamped to maxDelay.
    public func delay(forAttempt attempt: Int) -> TimeInterval {
        min(baseDelay * pow(2.0, Double(attempt)), maxDelay)
    }

    public static let `default` = RetryPolicy(maxAttempts: 3, baseDelay: 0.1, maxDelay: 2.0)
    public static let aggressive = RetryPolicy(maxAttempts: 5, baseDelay: 0.05, maxDelay: 1.0)
    public static let none = RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0)
}
