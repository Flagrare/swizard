import Foundation
import DBIProtocol

/// Timestamped log entry with severity level.
public struct LogEntry: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let message: String
    public let level: LogLevel

    public init(message: String, level: LogLevel = .info) {
        self.message = message
        self.level = level
    }
}
