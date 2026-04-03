import Foundation

/// Parsed HTTP request (Value Object).
public struct HTTPRequest: Sendable {
    public let method: String
    public let path: String
    public let range: HTTPRange?

    /// Parse a raw HTTP request string into structured data.
    public static func parse(_ raw: String) throws -> HTTPRequest {
        let lines = raw.components(separatedBy: "\r\n")
        guard let requestLine = lines.first, !requestLine.isEmpty else {
            throw HTTPParseError.emptyRequest
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            throw HTTPParseError.invalidRequestFormat
        }

        let method = String(parts[0])
        let path = String(parts[1])

        // Find Range header
        var range: HTTPRange?
        for line in lines.dropFirst() {
            let lower = line.lowercased()
            if lower.hasPrefix("range:") {
                let value = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                range = try? HTTPRange.parse(value)
                break
            }
        }

        return HTTPRequest(method: method, path: path, range: range)
    }

    /// Extract file index from path like "/0", "/1", "/42".
    public static func fileIndex(from path: String) -> Int? {
        let stripped = path.hasPrefix("/") ? String(path.dropFirst()) : path
        return Int(stripped)
    }
}
