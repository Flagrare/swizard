import Foundation

public enum DBIError: LocalizedError, Equatable {
    case invalidMagic(Data)
    case invalidHeaderSize(Int)
    case unknownCommand(UInt32)
    case unknownCommandType(UInt32)
    case invalidPayloadSize(Int)
    case fileNameDecodingFailed

    public var errorDescription: String? {
        switch self {
        case .invalidMagic(let data):
            "Invalid magic bytes: \(data.map { String(format: "%02X", $0) }.joined())"
        case .invalidHeaderSize(let size):
            "Invalid header size: \(size) bytes (expected \(DBIConstants.headerSize))"
        case .unknownCommand(let id):
            "Unknown DBI command: \(id)"
        case .unknownCommandType(let type):
            "Unknown DBI command type: \(type)"
        case .invalidPayloadSize(let size):
            "Invalid payload size: \(size) bytes"
        case .fileNameDecodingFailed:
            "Failed to decode file name as UTF-8"
        }
    }
}
