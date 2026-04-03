import Foundation

/// 16-byte DBI0 protocol header (value object).
/// Layout: magic(4B) + commandType(4B LE) + commandID(4B LE) + dataSize(4B LE)
public struct DBIHeader: Equatable, Sendable {
    public let commandType: DBICommandType
    public let commandID: DBICommand
    public let dataSize: UInt32

    public init(commandType: DBICommandType, commandID: DBICommand, dataSize: UInt32) {
        self.commandType = commandType
        self.commandID = commandID
        self.dataSize = dataSize
    }

    /// Decode from raw 16-byte data received over USB.
    public init(from data: Data) throws {
        guard data.count >= DBIConstants.headerSize else {
            throw DBIError.invalidHeaderSize(data.count)
        }

        let magic = data[data.startIndex..<data.startIndex + 4]
        guard magic == DBIConstants.magic else {
            throw DBIError.invalidMagic(Data(magic))
        }

        let rawType = data.loadLittleEndianUInt32(at: 4)
        guard let type = DBICommandType(rawValue: rawType) else {
            throw DBIError.unknownCommandType(rawType)
        }

        let rawCommand = data.loadLittleEndianUInt32(at: 8)
        guard let command = DBICommand(rawValue: rawCommand) else {
            throw DBIError.unknownCommand(rawCommand)
        }

        let size = data.loadLittleEndianUInt32(at: 12)

        self.commandType = type
        self.commandID = command
        self.dataSize = size
    }

    /// Encode to 16 bytes for sending over USB.
    public func encoded() -> Data {
        var data = Data(capacity: DBIConstants.headerSize)
        data.append(DBIConstants.magic)
        data.appendLittleEndian(commandType.rawValue)
        data.appendLittleEndian(commandID.rawValue)
        data.appendLittleEndian(dataSize)
        return data
    }
}

// MARK: - Data helpers for little-endian encoding

extension Data {
    func loadLittleEndianUInt32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        let start = startIndex + offset
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            copyBytes(to: dest, from: start..<start + 4)
        }
        return UInt32(littleEndian: value)
    }

    func loadLittleEndianUInt64(at offset: Int) -> UInt64 {
        var value: UInt64 = 0
        let start = startIndex + offset
        _ = Swift.withUnsafeMutableBytes(of: &value) { dest in
            copyBytes(to: dest, from: start..<start + 8)
        }
        return UInt64(littleEndian: value)
    }

    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndian(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
