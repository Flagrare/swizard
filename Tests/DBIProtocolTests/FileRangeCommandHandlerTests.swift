import XCTest
@testable import DBIProtocol

final class FileRangeCommandHandlerTests: XCTestCase {

    func testFileRangeCommandFollowsCorrectProtocolSequence() async throws {
        // Arrange: file with known content
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let content = Data(repeating: 0x42, count: 1024)
        fileServer.register(name: "test.nsp", content: content)

        let fileName = "test.nsp"
        let fileNameData = Data(fileName.utf8)

        // Build the FILE_RANGE payload: request 512 bytes at offset 0
        var payload = Data()
        payload.appendLittleEndian(UInt32(512))
        payload.appendLittleEndian(UInt64(0))
        payload.appendLittleEndian(UInt32(fileNameData.count))
        payload.append(fileNameData)

        let requestHeader = DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count))

        // Queue the Switch side: after our ACK, Switch sends payload; after our RESPONSE, Switch sends ACK
        transport.queueRead(payload)                   // payload sent after our ACK
        let switchAck = DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0)
        transport.queueRead(switchAck.encoded())       // ACK after our RESPONSE header

        let handler = FileRangeCommandHandler()

        // Act
        let result = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer
        )

        // Assert: should continue
        XCTAssertEqual(result, .continue)

        // Assert: handler wrote exactly 3 things — ACK header, RESPONSE header, file data
        XCTAssertEqual(transport.writtenData.count, 3)

        // Write 0: ACK header (acknowledging the FILE_RANGE request)
        let ackHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(ackHeader.commandType, .ack)
        XCTAssertEqual(ackHeader.commandID, .fileRange)
        XCTAssertEqual(ackHeader.dataSize, requestHeader.dataSize)

        // Write 1: RESPONSE header with file data size
        let responseHeader = try transport.writtenHeader(at: 1)
        XCTAssertEqual(responseHeader.commandType, .response)
        XCTAssertEqual(responseHeader.commandID, .fileRange)
        XCTAssertEqual(responseHeader.dataSize, 512)

        // Write 2: the actual file data
        let sentData = transport.writtenData[2]
        XCTAssertEqual(sentData.count, 512)
        XCTAssertEqual(sentData, Data(repeating: 0x42, count: 512))
    }

    func testFileRangeCommandWithOffset() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        var content = Data(repeating: 0x00, count: 100)
        content.append(Data(repeating: 0xFF, count: 200))
        fileServer.register(name: "offset.nsp", content: content)

        let fileName = "offset.nsp"
        let fileNameData = Data(fileName.utf8)

        var payload = Data()
        payload.appendLittleEndian(UInt32(50))
        payload.appendLittleEndian(UInt64(100))
        payload.appendLittleEndian(UInt32(fileNameData.count))
        payload.append(fileNameData)

        let requestHeader = DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count))
        transport.queueRead(payload)
        transport.queueRead(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0).encoded())

        let handler = FileRangeCommandHandler()
        _ = try await handler.handle(header: requestHeader, transport: transport, fileServer: fileServer)

        // Write 0: ACK, Write 1: RESPONSE header, Write 2: file data
        let sentData = transport.writtenData[2]
        XCTAssertEqual(sentData, Data(repeating: 0xFF, count: 50))
    }

    func testFileRangeCommandIDIsCorrect() {
        let handler = FileRangeCommandHandler()
        XCTAssertEqual(handler.commandID, .fileRange)
    }
}

extension Data {
    mutating func appendLittleEndian(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
    mutating func appendLittleEndian(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }
}
