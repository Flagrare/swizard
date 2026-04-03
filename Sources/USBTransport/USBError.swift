import Foundation

public enum USBError: LocalizedError, Equatable {
    case deviceNotFound
    case claimFailed(Int32)
    case transferFailed(Int32)
    case timeout
    case disconnected
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: "Nintendo Switch not found"
        case .claimFailed(let code): "Failed to claim USB interface (error: \(code))"
        case .transferFailed(let code): "USB transfer failed (error: \(code))"
        case .timeout: "USB transfer timed out"
        case .disconnected: "Switch disconnected"
        case .notConnected: "Not connected to Switch"
        }
    }
}
