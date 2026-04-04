import Foundation

/// Parses curl progress output (pure function, no side effects).
/// curl with --progress-bar outputs lines ending in percentage like "7.2%" or "100.0%".
public enum CurlProgressParser {

    public struct Progress: Sendable {
        public let percentage: Double

        /// Calculate bytes uploaded given the total file size.
        public func bytesUploaded(totalSize: UInt64) -> UInt64 {
            UInt64(Double(totalSize) * percentage / 100.0)
        }
    }

    /// Parse a curl progress line. Returns nil if line doesn't contain progress.
    public static func parse(_ line: String) -> Progress? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Look for percentage at the end: "7.2%" or "100.0%"
        guard trimmed.hasSuffix("%") else { return nil }

        // Extract the number before %
        let withoutPercent = String(trimmed.dropLast())
        let parts = withoutPercent.split(separator: " ")
        guard let lastPart = parts.last, let value = Double(lastPart) else { return nil }
        guard value >= 0 && value <= 100 else { return nil }

        return Progress(percentage: value)
    }
}
