import Foundation

/// Immutable snapshot of transfer metrics (Value Object + Null Object pattern).
public struct TransferStats: Sendable, Equatable {
    public let bytesPerSecond: Double
    public let estimatedTimeRemaining: TimeInterval?
    public let elapsedTime: TimeInterval

    public init(bytesPerSecond: Double, estimatedTimeRemaining: TimeInterval?, elapsedTime: TimeInterval) {
        self.bytesPerSecond = bytesPerSecond
        self.estimatedTimeRemaining = estimatedTimeRemaining
        self.elapsedTime = elapsedTime
    }

    /// Null Object: zero speed, no ETA, no elapsed time.
    public static let zero = TransferStats(bytesPerSecond: 0, estimatedTimeRemaining: nil, elapsedTime: 0)

    /// Formatted speed string (e.g., "12.3 MB/s").
    public var formattedSpeed: String {
        let mbPerSecond = bytesPerSecond / 1_000_000
        if mbPerSecond >= 1 {
            return String(format: "%.1f MB/s", mbPerSecond)
        } else {
            let kbPerSecond = bytesPerSecond / 1_000
            return String(format: "%.0f KB/s", kbPerSecond)
        }
    }

    /// Formatted ETA string (e.g., "~2m 15s").
    public var formattedETA: String? {
        guard let eta = estimatedTimeRemaining, eta > 0 else { return nil }
        let minutes = Int(eta) / 60
        let seconds = Int(eta) % 60
        if minutes > 0 {
            return "~\(minutes)m \(seconds)s"
        } else {
            return "~\(seconds)s"
        }
    }
}
