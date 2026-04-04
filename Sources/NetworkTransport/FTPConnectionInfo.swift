import Foundation

/// Connection details for DBI's FTP server (Value Object).
public struct FTPConnectionInfo: Sendable, Equatable {
    public let host: String
    public let port: UInt16

    public init(host: String, port: UInt16 = DBIFTPConstants.defaultPort) {
        self.host = host
        self.port = port
    }

    /// Constructs the FTP upload URL for a given filename (URL-encoded).
    public func uploadURL(for filename: String) -> String {
        let encoded = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return "ftp://\(host):\(port)/\(encoded)"
    }

    /// User-friendly display string (e.g., "192.168.0.96:5000").
    public var displayString: String {
        "\(host):\(port)"
    }

    /// Parse user input like "192.168.0.96:5000" or "192.168.0.96".
    public static func parse(_ input: String) -> FTPConnectionInfo? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let colonIndex = trimmed.lastIndex(of: ":") {
            let host = String(trimmed[..<colonIndex])
            let portStr = String(trimmed[trimmed.index(after: colonIndex)...])
            guard let port = UInt16(portStr), !host.isEmpty else { return nil }
            return FTPConnectionInfo(host: host, port: port)
        }

        return FTPConnectionInfo(host: trimmed)
    }
}
