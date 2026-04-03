import Foundation
import DBIProtocol

/// Decorator: wraps any TransportProtocol with retry logic + stall recovery.
/// Does not modify the inner transport (Open/Closed Principle).
/// Retries only on errors classified as retryable by USBError.isRetryable.
public final class RetryableTransport: TransportProtocol, @unchecked Sendable {
    private let inner: any TransportProtocol
    private let policy: RetryPolicy
    private let onStallRecovery: (() -> Void)?

    public init(
        inner: any TransportProtocol,
        policy: RetryPolicy = .default,
        onStallRecovery: (() -> Void)? = nil
    ) {
        self.inner = inner
        self.policy = policy
        self.onStallRecovery = onStallRecovery
    }

    public func connect() async throws {
        try await inner.connect()
    }

    public func disconnect() async throws {
        try await inner.disconnect()
    }

    public func read(maxLength: Int) async throws -> Data {
        try await withRetry { [inner] in
            try await inner.read(maxLength: maxLength)
        }
    }

    public func write(_ data: Data) async throws {
        try await withRetry { [inner] in
            try await inner.write(data)
        }
    }

    // MARK: - Private

    private func withRetry<T>(_ operation: @escaping () async throws -> T) async throws -> T {
        var lastError: any Error = USBError.timeout

        for attempt in 0..<policy.maxAttempts {
            do {
                return try await operation()
            } catch let error as USBError {
                lastError = error

                guard error.isRetryable else { throw error }

                if error.requiresStallRecovery {
                    onStallRecovery?()
                }

                if attempt < policy.maxAttempts - 1 {
                    let delay = policy.delay(forAttempt: attempt)
                    if delay > 0 {
                        try? await Task.sleep(for: .seconds(delay))
                    }
                }
            }
        }

        throw lastError
    }
}
