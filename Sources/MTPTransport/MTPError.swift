import Foundation

public enum MTPError: LocalizedError, Equatable {
    case deviceNotFound
    case connectionFailed(String)
    case storageNotFound
    case installFolderNotFound(String)
    case transferFailed(String)
    case cancelled
    case noStorage

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: "No MTP device found"
        case .connectionFailed(let detail): "MTP connection failed: \(detail)"
        case .storageNotFound: "No storage found on device"
        case .installFolderNotFound(let name): "Install folder '\(name)' not found on device"
        case .transferFailed(let detail): "MTP transfer failed: \(detail)"
        case .cancelled: "Transfer cancelled"
        case .noStorage: "Device has no storage"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .transferFailed: return true
        case .connectionFailed: return true
        default: return false
        }
    }
}
