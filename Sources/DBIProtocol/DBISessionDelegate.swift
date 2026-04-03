import Foundation

/// Delegate for observing DBI session events (progress, logging).
/// Implemented by InstallationCoordinator to bridge protocol events to the UI.
public protocol DBISessionDelegate: AnyObject, Sendable {
    func sessionDidLog(_ message: String)
    func sessionDidSendFileChunk(fileName: String, bytesInChunk: UInt32, totalOffset: UInt64)
    func sessionDidReceiveExit()
}
