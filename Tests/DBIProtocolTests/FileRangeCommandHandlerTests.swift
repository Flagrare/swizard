import XCTest
@testable import DBIProtocol

final class FileRangeCommandHandlerTests: XCTestCase {

    func testFileRangeCommandSendsRequestedChunk() async throws {
        // Arrange: file with known content
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let content = Data(repeating: 0x42, count: 1024)
        fileServer.register(name: "test.nsp", content: content)

        let fileName = "test.nsp"
        let fileNameData = Data(fileName.utf8)

        // Build the FILE_RANGE payload: request 512 bytes at offset 0
        var payload = Data()
        payload.appendLittleEndian(UInt32(512))        // rangeSize
        payload.appendLittleEndian(UInt64(0))           // rangeOffset
        payload.appendLittleEndian(UInt32(fileNameData.count)) // nameLen
        payload.append(fileNameData)

        let requestHeader = DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count))

        // Queue: the payload read, then ACK after our response header
        transport.queueRead(payload)
        let ackHeader = DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0)
        transport.queueRead(ackHeader.encoded())

        let handler = FileRangeCommandHandler()

        // Act
        let result = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer
        )

        // Assert
        XCTAssertEqual(result, .continue)

        // Writes: RESPONSE header, then file data
        XCTAssertEqual(transport.writtenData.count, 2)

        let responseHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(responseHeader.commandType, .response)
        XCTAssertEqual(responseHeader.commandID, .fileRange)
        XCTAssertEqual(responseHeader.dataSize, 512)

        // The actual file data
        let sentData = transport.writtenData[1]
        XCTAssertEqual(sentData.count, 512)
        XCTAssertEqual(sentData, Data(repeating: 0x42, count: 512))
    }

    func testFileRangeCommandWithOffset() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        // Create content where offset 100 starts with 0xFF bytes
        var content = Data(repeating: 0x00, count: 100)
        content.append(Data(repeating: 0xFF, count: 200))
        fileServer.register(name: "offset.nsp", content: content)

        let fileName = "offset.nsp"
        let fileNameData = Data(fileName.utf8)

        var payload = Data()
        payload.appendLittleEndian(UInt32(50))          // rangeSize: 50 bytes
        payload.appendLittleEndian(UInt64(100))         // rangeOffset: start at 100
        payload.appendLittleEndian(UInt32(fileNameData.count))
        payload.append(fileNameData)

        let requestHeader = DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count))
        transport.queueRead(payload)
        transport.queueRead(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0).encoded())

        let handler = FileRangeCommandHandler()
        _ = try await handler.handle(header: requestHeader, transport: transport, fileServer: fileServer)

        // Should send 50 bytes of 0xFF (from offset 100)
        let sentData = transport.writtenData[1]
        XCTAssertEqual(sentData, Data(repeating: 0xFF, count: 50))
    }

    func testFileRangeCommandIDIsCorrect() {
        let handler = FileRangeCommandHandler()
        XCTAssertEqual(handler.commandID, .fileRange)
    }
}

// Helper to use the same Data extension from DBIProtocol in tests
extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLittleEndian(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
