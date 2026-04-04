import Foundation

/// Abstraction for FTP file uploads (Strategy pattern).
/// Enables MockFTPUploadClient for TDD.
public protocol FTPUploadClientProtocol: Sendable {
    func upload(
        file: URL,
        to connection: FTPConnectionInfo,
        onProgress: @escaping @Sendable (Double) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws
}
