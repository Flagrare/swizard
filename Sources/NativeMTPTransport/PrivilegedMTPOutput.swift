import Foundation

/// Parses stdout lines from the privileged MTP helper process.
/// Protocol: PROGRESS:filename:sent:total | OK | ERROR:message | LOG:message
public enum PrivilegedMTPOutput: Equatable, Sendable {
    case progress(fileName: String, bytesSent: UInt64, totalBytes: UInt64)
    case success
    case error(String)
    case log(String)

    public static func parse(_ line: String) -> PrivilegedMTPOutput {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed == "OK" {
            return .success
        }

        if trimmed.hasPrefix("PROGRESS:") {
            let parts = trimmed.dropFirst(9).split(separator: ":", maxSplits: 2)
            if parts.count == 3,
               let sent = UInt64(parts[1]),
               let total = UInt64(parts[2]) {
                return .progress(fileName: String(parts[0]), bytesSent: sent, totalBytes: total)
            }
        }

        if trimmed.hasPrefix("ERROR:") {
            return .error(String(trimmed.dropFirst(6)))
        }

        if trimmed.hasPrefix("LOG:") {
            return .log(String(trimmed.dropFirst(4)))
        }

        return .log(trimmed)
    }
}
