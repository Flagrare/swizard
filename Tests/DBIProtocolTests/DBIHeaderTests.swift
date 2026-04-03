import XCTest
@testable import DBIProtocol

final class DBIHeaderTests: XCTestCase {

    // MARK: - Encoding

    func testEncodeResponseListHeader() throws {
        let header = DBIHeader(
            commandType: .response,
            commandID: .list,
            dataSize: 42
        )
        let data = header.encoded()

        XCTAssertEqual(data.count, 16)
        // Magic: "DBI0"
        XCTAssertEqual(data[0], 0x44) // D
        XCTAssertEqual(data[1], 0x42) // B
        XCTAssertEqual(data[2], 0x49) // I
        XCTAssertEqual(data[3], 0x30) // 0
        // Command type: RESPONSE = 1 (little-endian UInt32)
        XCTAssertEqual(data[4], 0x01)
        XCTAssertEqual(data[5], 0x00)
        XCTAssertEqual(data[6], 0x00)
        XCTAssertEqual(data[7], 0x00)
        // Command ID: LIST = 3 (little-endian UInt32)
        XCTAssertEqual(data[8], 0x03)
        XCTAssertEqual(data[9], 0x00)
        XCTAssertEqual(data[10], 0x00)
        XCTAssertEqual(data[11], 0x00)
        // Data size: 42 (little-endian UInt32)
        XCTAssertEqual(data[12], 0x2A)
        XCTAssertEqual(data[13], 0x00)
        XCTAssertEqual(data[14], 0x00)
        XCTAssertEqual(data[15], 0x00)
    }

    func testEncodeAckHeader() throws {
        let header = DBIHeader(
            commandType: .ack,
            commandID: .fileRange,
            dataSize: 0
        )
        let data = header.encoded()

        XCTAssertEqual(data.count, 16)
        // Command type: ACK = 2
        XCTAssertEqual(data[4], 0x02)
        // Command ID: FILE_RANGE = 2
        XCTAssertEqual(data[8], 0x02)
        // Data size: 0
        XCTAssertEqual(data[12], 0x00)
    }

    // MARK: - Decoding

    func testDecodeRequestListHeader() throws {
        // Build a raw 16-byte packet: DBI0 + REQUEST(0) + LIST(3) + size(100)
        var data = Data("DBI0".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(100).littleEndian) { Data($0) })

        let header = try DBIHeader(from: data)
        XCTAssertEqual(header.commandType, .request)
        XCTAssertEqual(header.commandID, .list)
        XCTAssertEqual(header.dataSize, 100)
    }

    // MARK: - Round-trip

    func testEncodeDecodeRoundTrip() throws {
        let original = DBIHeader(
            commandType: .response,
            commandID: .fileRange,
            dataSize: 1_048_576
        )
        let decoded = try DBIHeader(from: original.encoded())

        XCTAssertEqual(decoded.commandType, original.commandType)
        XCTAssertEqual(decoded.commandID, original.commandID)
        XCTAssertEqual(decoded.dataSize, original.dataSize)
    }

    // MARK: - Error cases

    func testDecodeInvalidMagicThrows() {
        var data = Data("XXXX".utf8)
        data.append(contentsOf: [UInt8](repeating: 0, count: 12))

        XCTAssertThrowsError(try DBIHeader(from: data)) { error in
            guard let dbiError = error as? DBIError else {
                return XCTFail("Expected DBIError, got \(error)")
            }
            if case .invalidMagic = dbiError { } else {
                XCTFail("Expected .invalidMagic, got \(dbiError)")
            }
        }
    }

    func testDecodeTooShortThrows() {
        let data = Data("DBI0".utf8) // Only 4 bytes, need 16

        XCTAssertThrowsError(try DBIHeader(from: data)) { error in
            guard let dbiError = error as? DBIError else {
                return XCTFail("Expected DBIError, got \(error)")
            }
            if case .invalidHeaderSize = dbiError { } else {
                XCTFail("Expected .invalidHeaderSize, got \(dbiError)")
            }
        }
    }

    func testDecodeUnknownCommandThrows() {
        var data = Data("DBI0".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(99).littleEndian) { Data($0) }) // Unknown command
        data.append(contentsOf: withUnsafeBytes(of: UInt32(0).littleEndian) { Data($0) })

        XCTAssertThrowsError(try DBIHeader(from: data)) { error in
            guard let dbiError = error as? DBIError else {
                return XCTFail("Expected DBIError, got \(error)")
            }
            if case .unknownCommand = dbiError { } else {
                XCTFail("Expected .unknownCommand, got \(dbiError)")
            }
        }
    }

    func testDecodeMaxDataSize() throws {
        var data = Data("DBI0".utf8)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(3).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32.max.littleEndian) { Data($0) })

        let header = try DBIHeader(from: data)
        XCTAssertEqual(header.dataSize, UInt32.max)
    }
}
