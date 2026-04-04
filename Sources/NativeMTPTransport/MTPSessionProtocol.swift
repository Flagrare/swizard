import Foundation

/// Abstraction for MTP session execution (Strategy pattern).
/// Enables mock injection for tests — no admin password prompts.
public protocol MTPSessionProtocol: Sendable {
    func install(
        files: [PrivilegedMTPSession.FileToInstall],
        onProgress: @escaping @Sendable (String, UInt64, UInt64) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws
}

extension PrivilegedMTPSession: MTPSessionProtocol {}
