import Foundation

/// Policy Object: configures session reconnect behavior on USB disconnect.
public struct ReconnectPolicy: Sendable, Equatable {
    public let maxAttempts: Int
    public let baseDelay: TimeInterval

    public init(maxAttempts: Int, baseDelay: TimeInterval) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
    }

    public static let `default` = ReconnectPolicy(maxAttempts: 3, baseDelay: 2.0)
    public static let none = ReconnectPolicy(maxAttempts: 0, baseDelay: 0)
}
