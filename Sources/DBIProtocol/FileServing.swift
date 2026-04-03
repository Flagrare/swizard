import Foundation

/// Abstraction for file access (Dependency Inversion).
/// The domain defines what it needs; the Installer layer provides the implementation.
public protocol FileServing: Sendable {
    func fileList() -> String
    func readRange(fileName: String, offset: UInt64, size: UInt32) throws -> Data
}
