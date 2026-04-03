import Foundation

/// Sliding-window speed calculator (SRP: only computes rates, no IO).
/// Keeps samples from the last N seconds and computes deltaBytes/deltaTime.
public final class SpeedCalculator: @unchecked Sendable {
    private var samples: [(timestamp: Date, totalBytes: UInt64)] = []
    private let windowSize: TimeInterval
    private let startTime: Date

    public init(startTime: Date = Date(), windowSize: TimeInterval = 3.0) {
        self.startTime = startTime
        self.windowSize = windowSize
    }

    public func addSample(totalBytes: UInt64, at timestamp: Date = Date()) {
        samples.append((timestamp: timestamp, totalBytes: totalBytes))
        pruneOldSamples(relativeTo: timestamp)
    }

    public func currentStats(totalBytes: UInt64, remainingBytes: UInt64) -> TransferStats {
        let now = samples.last?.timestamp ?? Date()
        let elapsed = now.timeIntervalSince(startTime)
        let speed = computeSpeed()

        let eta: TimeInterval?
        if speed > 0 && remainingBytes > 0 {
            eta = Double(remainingBytes) / speed
        } else if remainingBytes == 0 {
            eta = 0
        } else {
            eta = nil
        }

        return TransferStats(
            bytesPerSecond: speed,
            estimatedTimeRemaining: eta,
            elapsedTime: elapsed
        )
    }

    // MARK: - Private

    private func computeSpeed() -> Double {
        guard samples.count >= 2 else { return 0 }

        let oldest = samples.first!
        let newest = samples.last!
        let deltaTime = newest.timestamp.timeIntervalSince(oldest.timestamp)

        guard deltaTime > 0 else { return 0 }

        let deltaBytes = Double(newest.totalBytes) - Double(oldest.totalBytes)
        return max(deltaBytes / deltaTime, 0)
    }

    private func pruneOldSamples(relativeTo now: Date) {
        let cutoff = now.addingTimeInterval(-windowSize)
        samples.removeAll { $0.timestamp < cutoff }
    }
}
