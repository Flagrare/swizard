import Foundation

/// Log severity levels (Value Object).
/// Lives in DBIProtocol so the delegate protocol and all layers above can use it (DIP).
public enum LogLevel: Int, Comparable, Sendable, CaseIterable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
