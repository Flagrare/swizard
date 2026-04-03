import Foundation

public enum USBError: LocalizedError, Equatable {
    case deviceNotFound
    case initializationFailed(Int32)
    case claimFailed(Int32)
    case transferFailed(Int32)
    case timeout
    case disconnected
    case notConnected

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: "Nintendo Switch not found"
        case .initializationFailed(let code): "USB initialization failed (error: \(code)). Check libusb installation."
        case .claimFailed(let code): "Failed to claim USB interface (error: \(code))"
        case .transferFailed(let code): "USB transfer failed (error: \(code))"
        case .timeout: "USB transfer timed out"
        case .disconnected: "Switch disconnected"
        case .notConnected: "Not connected to Switch"
        }
    }

    /// Whether this error is transient and the operation should be retried.
    public var isRetryable: Bool {
        switch self {
        case .timeout: return true
        case .transferFailed(let code):
            // PIPE (-9), OVERFLOW (-8), INTERRUPTED (-10)
            return code == -9 || code == -8 || code == -10
        case .disconnected, .deviceNotFound, .claimFailed, .notConnected, .initializationFailed:
            return false
        }
    }

    /// Whether this error indicates an endpoint stall requiring libusb_clear_halt.
    public var requiresStallRecovery: Bool {
        if case .transferFailed(let code) = self { return code == -9 }
        return false
    }
}
