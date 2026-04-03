import Foundation

public enum InstallError: LocalizedError {
    case fileNotFound(String)
    case fileReadFailed(String, any Error)
    case cancelled
    case connectionLost

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let name): "File not found: \(name)"
        case .fileReadFailed(let name, let error): "Failed to read \(name): \(error.localizedDescription)"
        case .cancelled: "Installation cancelled"
        case .connectionLost: "Connection to Switch lost"
        }
    }
}
