import XCTest
@testable import NativeMTPTransport

final class MTPContainerTests: XCTestCase {

    // MARK: - Encoding

    func testEncodeCommandContainer() {
        let container = MTPContainer(
            type: .command,
            code: MTPOperation.openSession.rawValue,
            transactionID: 1,
            payload: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) } // sessionID = 1
        )

        let data = container.encoded()

        // Header: 4(length) + 2(type) + 2(code) + 4(txID) = 12 + 4(payload) = 16
        XCTAssertEqual(data.count, 16)

        // Length field (LE)
        let length = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: length), 16)

        // Type field (LE) — Command = 0x0001
        let type = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 4, as: UInt16.self) }
        XCTAssertEqual(UInt16(littleEndian: type), 0x0001)

        // Code field (LE) — OpenSession = 0x1002
        let code = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: UInt16.self) }
        XCTAssertEqual(UInt16(littleEndian: code), 0x1002)

        // Transaction ID (LE)
        let txID = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 8, as: UInt32.self) }
        XCTAssertEqual(UInt32(littleEndian: txID), 1)
    }

    func testEncodeEmptyPayloadContainer() {
        let container = MTPContainer(
            type: .command,
            code: MTPOperation.closeSession.rawValue,
            transactionID: 5,
            payload: Data()
        )

        let data = container.encoded()
        XCTAssertEqual(data.count, 12) // header only, no payload
    }

    // MARK: - Decoding

    func testDecodeResponseContainer() throws {
        // Build a raw OK response: length=12, type=Response(3), code=OK(0x2001), txID=1
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(12).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0003).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x2001).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })

        let container = try MTPContainer(from: data)

        XCTAssertEqual(container.type, .response)
        XCTAssertEqual(container.code, MTPResponseCode.ok.rawValue)
        XCTAssertEqual(container.transactionID, 1)
        XCTAssertTrue(container.payload.isEmpty)
    }

    func testDecodeDataContainerWithPayload() throws {
        // Data container with 4 bytes of payload
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0002).littleEndian) { Data($0) }) // Data type
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x1004).littleEndian) { Data($0) }) // GetStorageIDs
        data.append(contentsOf: withUnsafeBytes(of: UInt32(2).littleEndian) { Data($0) })      // txID
        data.append(contentsOf: [0xAA, 0xBB, 0xCC, 0xDD])                                     // payload

        let container = try MTPContainer(from: data)

        XCTAssertEqual(container.type, .data)
        XCTAssertEqual(container.transactionID, 2)
        XCTAssertEqual(container.payload, Data([0xAA, 0xBB, 0xCC, 0xDD]))
    }

    // MARK: - Round-trip

    func testEncodeDecodeRoundTrip() throws {
        let original = MTPContainer(
            type: .command,
            code: MTPOperation.getStorageIDs.rawValue,
            transactionID: 42,
            payload: Data([0x01, 0x02, 0x03])
        )

        let decoded = try MTPContainer(from: original.encoded())

        XCTAssertEqual(decoded.type, original.type)
        XCTAssertEqual(decoded.code, original.code)
        XCTAssertEqual(decoded.transactionID, original.transactionID)
        XCTAssertEqual(decoded.payload, original.payload)
    }

    // MARK: - Error cases

    func testDecodeTooShortThrows() {
        let data = Data([0x01, 0x02, 0x03]) // only 3 bytes, need 12
        XCTAssertThrowsError(try MTPContainer(from: data))
    }

    func testDecodeInvalidContainerTypeThrows() {
        var data = Data()
        data.append(contentsOf: withUnsafeBytes(of: UInt32(12).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x0099).littleEndian) { Data($0) }) // invalid type
        data.append(contentsOf: withUnsafeBytes(of: UInt16(0x1001).littleEndian) { Data($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) })

        XCTAssertThrowsError(try MTPContainer(from: data))
    }

    // MARK: - Operation codes

    func testOperationCodes() {
        XCTAssertEqual(MTPOperation.openSession.rawValue, 0x1002)
        XCTAssertEqual(MTPOperation.closeSession.rawValue, 0x1003)
        XCTAssertEqual(MTPOperation.getStorageIDs.rawValue, 0x1004)
        XCTAssertEqual(MTPOperation.getObjectHandles.rawValue, 0x1007)
        XCTAssertEqual(MTPOperation.sendObjectInfo.rawValue, 0x100C)
        XCTAssertEqual(MTPOperation.sendObject.rawValue, 0x100D)
    }

    func testResponseCodes() {
        XCTAssertEqual(MTPResponseCode.ok.rawValue, 0x2001)
        XCTAssertEqual(MTPResponseCode.generalError.rawValue, 0x2002)
        XCTAssertEqual(MTPResponseCode.sessionNotOpen.rawValue, 0x2003)
    }
}
