import Foundation

/// Parsed HTTP Range header value (Value Object).
public struct HTTPRange: Sendable, Equatable {
    public let start: UInt64
    public let end: UInt64?

    public init(start: UInt64, end: UInt64?) {
        self.start = start
        self.end = end
    }

    /// Parse a "bytes=X-Y" or "bytes=X-" range header value.
    public static func parse(_ value: String) throws -> HTTPRange {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("bytes=") else {
            throw HTTPParseError.invalidRangeFormat(value)
        }

        let rangeStr = String(trimmed.dropFirst(6))
        let parts = rangeStr.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)

        guard let startStr = parts.first, let start = UInt64(startStr) else {
            throw HTTPParseError.invalidRangeFormat(value)
        }

        let end: UInt64?
        if parts.count > 1 && !parts[1].isEmpty {
            guard let endVal = UInt64(parts[1]) else {
                throw HTTPParseError.invalidRangeFormat(value)
            }
            end = endVal
        } else {
            end = nil
        }

        return HTTPRange(start: start, end: end)
    }
}

public enum HTTPParseError: LocalizedError, Equatable {
    case invalidRangeFormat(String)
    case invalidRequestFormat
    case emptyRequest

    public var errorDescription: String? {
        switch self {
        case .invalidRangeFormat(let v): "Invalid range format: \(v)"
        case .invalidRequestFormat: "Invalid HTTP request format"
        case .emptyRequest: "Empty HTTP request"
        }
    }
}
