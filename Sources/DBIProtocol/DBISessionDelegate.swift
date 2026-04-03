import Foundation

/// Delegate for observing DBI session events (progress, logging).
public protocol DBISessionDelegate: AnyObject, Sendable {
    func sessionDidReceiveListRequest()
    func sessionDidSendFileList(_ fileList: String)
    func sessionDidReceiveFileRange(fileName: String, offset: UInt64, size: UInt32)
    func sessionDidSendFileChunk(fileName: String, bytesSent: UInt64)
    func sessionDidReceiveExit()
    func sessionDidLog(_ message: String)
}
