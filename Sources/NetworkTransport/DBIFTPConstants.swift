import Foundation

/// Constants for DBI's FTP server.
public enum DBIFTPConstants {
    /// Default FTP port for DBI install mode.
    public static let defaultPort: UInt16 = 5000

    /// File extensions DBI accepts for auto-installation via FTP.
    public static let acceptedExtensions: Set<String> = ["nsp", "nsz", "xci", "xcz"]

    /// FTP credentials (DBI uses anonymous access).
    public static let username = "anonymous"
    public static let password = ""
}
