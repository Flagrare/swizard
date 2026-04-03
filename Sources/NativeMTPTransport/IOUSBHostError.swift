import Foundation

/// Errors for the IOUSBHost adapter layer.
public enum IOUSBHostError: LocalizedError, Equatable {
    case deviceNotFound
    case openFailed(String)
    case claimFailed(String)
    case readFailed(String)
    case writeFailed(String)
    case seizeRejected

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: "Nintendo Switch not found via IOUSBHost"
        case .openFailed(let d): "Failed to open USB device: \(d)"
        case .claimFailed(let d): "Failed to claim USB interface: \(d)"
        case .readFailed(let d): "USB read failed: \(d)"
        case .writeFailed(let d): "USB write failed: \(d)"
        case .seizeRejected: "macOS refused to release the USB device. Try unplugging and replugging the Switch."
        }
    }
}
