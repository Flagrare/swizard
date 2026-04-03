import XCTest
@testable import DBIProtocol

final class FileRangeRequestTests: XCTestCase {

    func testParseValidPayload() throws {
        let fileName = "Mario Kart 8.nsp"
        let fileNameData = Data(fileName.utf8)

        // Build payload: rangeSize(4B) + rangeOffset(8B) + nameLen(4B) + name
        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(1_048_576).littleEndian) { Data($0) }) // 1MB
        payload.append(contentsOf: withUnsafeBytes(of: UInt64(4_194_304).littleEndian) { Data($0) }) // offset 4MB
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(fileNameData.count).littleEndian) { Data($0) })
        payload.append(fileNameData)

        let request = try FileRangeRequest(from: payload)

        XCTAssertEqual(request.rangeSize, 1_048_576)
        XCTAssertEqual(request.rangeOffset, 4_194_304)
        XCTAssertEqual(request.fileName, "Mario Kart 8.nsp")
    }

    func testParseZeroOffset() throws {
        let fileName = "test.nsp"
        let fileNameData = Data(fileName.utf8)

        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(512).littleEndian) { Data($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt64(0).littleEndian) { Data($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(fileNameData.count).littleEndian) { Data($0) })
        payload.append(fileNameData)

        let request = try FileRangeRequest(from: payload)

        XCTAssertEqual(request.rangeOffset, 0)
        XCTAssertEqual(request.fileName, "test.nsp")
    }

    func testParseLargeOffset() throws {
        let fileName = "big.xci"
        let fileNameData = Data(fileName.utf8)

        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(1_048_576).littleEndian) { Data($0) })
        // 10 GB offset
        payload.append(contentsOf: withUnsafeBytes(of: UInt64(10_737_418_240).littleEndian) { Data($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(fileNameData.count).littleEndian) { Data($0) })
        payload.append(fileNameData)

        let request = try FileRangeRequest(from: payload)
        XCTAssertEqual(request.rangeOffset, 10_737_418_240)
    }

    func testParseTooShortPayloadThrows() {
        let payload = Data([0x00, 0x01, 0x02]) // Only 3 bytes, need at least 16

        XCTAssertThrowsError(try FileRangeRequest(from: payload)) { error in
            guard let dbiError = error as? DBIError else {
                return XCTFail("Expected DBIError")
            }
            if case .invalidPayloadSize = dbiError { } else {
                XCTFail("Expected .invalidPayloadSize, got \(dbiError)")
            }
        }
    }

    func testParseInvalidUTF8FileNameThrows() {
        var payload = Data()
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(100).littleEndian) { Data($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt64(0).littleEndian) { Data($0) })
        payload.append(contentsOf: withUnsafeBytes(of: UInt32(2).littleEndian) { Data($0) })
        payload.append(contentsOf: [0xFE, 0xFF]) // Invalid UTF-8

        XCTAssertThrowsError(try FileRangeRequest(from: payload)) { error in
            guard let dbiError = error as? DBIError else {
                return XCTFail("Expected DBIError")
            }
            if case .fileNameDecodingFailed = dbiError { } else {
                XCTFail("Expected .fileNameDecodingFailed, got \(dbiError)")
            }
        }
    }
}
