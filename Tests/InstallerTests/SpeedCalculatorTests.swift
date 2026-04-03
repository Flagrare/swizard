import XCTest
@testable import Installer

final class SpeedCalculatorTests: XCTestCase {

    func testSpeedFromTwoSamples() {
        let start = Date(timeIntervalSince1970: 1000)
        let calc = SpeedCalculator(startTime: start)

        calc.addSample(totalBytes: 0, at: start)
        calc.addSample(totalBytes: 10_000_000, at: start.addingTimeInterval(1.0)) // 10MB in 1s

        let stats = calc.currentStats(totalBytes: 10_000_000, remainingBytes: 10_000_000)

        XCTAssertEqual(stats.bytesPerSecond, 10_000_000, accuracy: 100)
    }

    func testETACalculation() {
        let start = Date(timeIntervalSince1970: 1000)
        let calc = SpeedCalculator(startTime: start)

        calc.addSample(totalBytes: 0, at: start)
        calc.addSample(totalBytes: 5_000_000, at: start.addingTimeInterval(1.0)) // 5MB/s

        // 10MB remaining at 5MB/s = 2 seconds ETA
        let stats = calc.currentStats(totalBytes: 5_000_000, remainingBytes: 10_000_000)

        XCTAssertNotNil(stats.estimatedTimeRemaining)
        XCTAssertEqual(stats.estimatedTimeRemaining!, 2.0, accuracy: 0.1)
    }

    func testElapsedTime() {
        let start = Date(timeIntervalSince1970: 1000)
        let now = start.addingTimeInterval(5.0)
        let calc = SpeedCalculator(startTime: start)

        calc.addSample(totalBytes: 100, at: now)

        let stats = calc.currentStats(totalBytes: 100, remainingBytes: 0)

        XCTAssertEqual(stats.elapsedTime, 5.0, accuracy: 0.5)
    }

    func testSlidingWindowIgnoresOldSamples() {
        let start = Date(timeIntervalSince1970: 1000)
        let calc = SpeedCalculator(startTime: start, windowSize: 3.0)

        // Old sample: 1MB at t=0
        calc.addSample(totalBytes: 1_000_000, at: start)
        // Old sample: 2MB at t=1 (will be outside 3s window relative to t=10)
        calc.addSample(totalBytes: 2_000_000, at: start.addingTimeInterval(1.0))

        // Recent samples within window
        calc.addSample(totalBytes: 50_000_000, at: start.addingTimeInterval(8.0))
        calc.addSample(totalBytes: 60_000_000, at: start.addingTimeInterval(10.0))

        let stats = calc.currentStats(totalBytes: 60_000_000, remainingBytes: 0)

        // Speed should be based on recent window: 10MB in 2s = 5MB/s
        XCTAssertEqual(stats.bytesPerSecond, 5_000_000, accuracy: 500_000)
    }

    func testZeroStatsWhenNoSamples() {
        let calc = SpeedCalculator(startTime: Date())

        let stats = calc.currentStats(totalBytes: 0, remainingBytes: 100)

        XCTAssertEqual(stats.bytesPerSecond, 0)
        XCTAssertNil(stats.estimatedTimeRemaining)
    }

    func testZeroStatsWhenOnlyOneSample() {
        let calc = SpeedCalculator(startTime: Date())
        calc.addSample(totalBytes: 1000, at: Date())

        let stats = calc.currentStats(totalBytes: 1000, remainingBytes: 500)

        // Can't compute speed from a single sample
        XCTAssertEqual(stats.bytesPerSecond, 0)
    }

    func testETAIsNilWhenTransferComplete() {
        let start = Date(timeIntervalSince1970: 1000)
        let calc = SpeedCalculator(startTime: start)

        calc.addSample(totalBytes: 0, at: start)
        calc.addSample(totalBytes: 100, at: start.addingTimeInterval(1.0))

        let stats = calc.currentStats(totalBytes: 100, remainingBytes: 0)

        // No remaining bytes → no ETA needed
        XCTAssertEqual(stats.estimatedTimeRemaining, 0)
    }
}
