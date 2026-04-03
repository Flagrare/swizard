import Foundation

/// MTP container types.
public enum MTPContainerType: UInt16, Sendable {
    case command  = 0x0001
    case data     = 0x0002
    case response = 0x0003
    case event    = 0x0004
}

/// MTP container (Value Object): 12-byte header + variable payload.
/// All fields are little-endian.
///
/// Layout: containerLength(4B) + containerType(2B) + code(2B) + transactionID(4B) + payload
public struct MTPContainer: Sendable, Equatable {
    public static let headerSize = 12

    public let type: MTPContainerType
    public let code: UInt16
    public let transactionID: UInt32
    public let payload: Data

    public init(type: MTPContainerType, code: UInt16, transactionID: UInt32, payload: Data = Data()) {
        self.type = type
        self.code = code
        self.transactionID = transactionID
        self.payload = payload
    }

    /// Encode to bytes for sending over USB.
    public func encoded() -> Data {
        let length = UInt32(Self.headerSize + payload.count)
        var data = Data(capacity: Int(length))

        Swift.withUnsafeBytes(of: length.littleEndian) { data.append(contentsOf: $0) }
        Swift.withUnsafeBytes(of: type.rawValue.littleEndian) { data.append(contentsOf: $0) }
        Swift.withUnsafeBytes(of: code.littleEndian) { data.append(contentsOf: $0) }
        Swift.withUnsafeBytes(of: transactionID.littleEndian) { data.append(contentsOf: $0) }
        data.append(payload)

        return data
    }

    /// Decode from raw bytes received over USB.
    public init(from data: Data) throws {
        guard data.count >= Self.headerSize else {
            throw MTPContainerError.tooShort(data.count)
        }

        let rawType = data.loadUInt16(at: 4)
        guard let type = MTPContainerType(rawValue: rawType) else {
            throw MTPContainerError.invalidContainerType(rawType)
        }

        self.type = type
        self.code = data.loadUInt16(at: 6)
        self.transactionID = data.loadUInt32(at: 8)

        if data.count > Self.headerSize {
            self.payload = data[data.startIndex + Self.headerSize..<data.endIndex]
        } else {
            self.payload = Data()
        }
    }
}

// MARK: - Errors

public enum MTPContainerError: LocalizedError, Equatable {
    case tooShort(Int)
    case invalidContainerType(UInt16)

    public var errorDescription: String? {
        switch self {
        case .tooShort(let size): "MTP container too short: \(size) bytes (need \(MTPContainer.headerSize))"
        case .invalidContainerType(let type): "Invalid MTP container type: 0x\(String(type, radix: 16))"
        }
    }
}

// MARK: - Data helpers

private extension Data {
    func loadUInt16(at offset: Int) -> UInt16 {
        var value: UInt16 = 0
        let start = startIndex + offset
        Swift.withUnsafeMutableBytes(of: &value) { dest in
            copyBytes(to: dest, from: start..<start + 2)
        }
        return UInt16(littleEndian: value)
    }

    func loadUInt32(at offset: Int) -> UInt32 {
        var value: UInt32 = 0
        let start = startIndex + offset
        Swift.withUnsafeMutableBytes(of: &value) { dest in
            copyBytes(to: dest, from: start..<start + 4)
        }
        return UInt32(littleEndian: value)
    }
}
