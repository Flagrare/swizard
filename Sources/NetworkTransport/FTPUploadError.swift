import Foundation

public enum FTPUploadError: LocalizedError, Equatable {
    case connectionFailed(String)
    case transferFailed(String)
    case cancelled
    case invalidFile(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let d): "FTP connection failed: \(d)"
        case .transferFailed(let d): "FTP transfer failed: \(d)"
        case .cancelled: "FTP transfer cancelled"
        case .invalidFile(let d): "Invalid file: \(d)"
        }
    }
}
