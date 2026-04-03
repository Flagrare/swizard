import XCTest
@testable import DBIProtocol

final class FileRangeCommandHandlerTests: XCTestCase {

    func testFileRangeCommandFollowsCorrectProtocolSequence() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let content = Data(repeating: 0x42, count: 1024)
        fileServer.register(name: "test.nsp", content: content)

        let fileName = "test.nsp"
        let fileNameData = Data(fileName.utf8)

        var payload = Data()
        payload.appendLittleEndian(UInt32(512))
        payload.appendLittleEndian(UInt64(0))
        payload.appendLittleEndian(UInt32(fileNameData.count))
        payload.append(fileNameData)

        let requestHeader = DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count))
        transport.queueRead(payload)
        transport.queueRead(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0).encoded())

        let handler = FileRangeCommandHandler()

        let result = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer,
            delegate: nil
        )

        XCTAssertEqual(result, .continue)
        // Writes: ACK header, RESPONSE header, file data
        XCTAssertEqual(transport.writtenData.count, 3)

        let ackHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(ackHeader.commandType, .ack)
        XCTAssertEqual(ackHeader.commandID, .fileRange)
        XCTAssertEqual(ackHeader.dataSize, requestHeader.dataSize)

        let responseHeader = try transport.writtenHeader(at: 1)
        XCTAssertEqual(responseHeader.commandType, .response)
        XCTAssertEqual(responseHeader.commandID, .fileRange)
        XCTAssertEqual(responseHeader.dataSize, 512)

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
        _ = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer,
            delegate: nil
        )

        let sentData = transport.writtenData[2]
        XCTAssertEqual(sentData, Data(repeating: 0xFF, count: 50))
    }

    func testFileRangeReportsProgressViaDelegate() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        fileServer.register(name: "game.nsp", content: Data(repeating: 0xAB, count: 500))

        let fileName = "game.nsp"
        let fileNameData = Data(fileName.utf8)

        var payload = Data()
        payload.appendLittleEndian(UInt32(200))   // request 200 bytes
        payload.appendLittleEndian(UInt64(100))   // at offset 100
        payload.appendLittleEndian(UInt32(fileNameData.count))
        payload.append(fileNameData)

        let requestHeader = DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count))
        transport.queueRead(payload)
        transport.queueRead(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0).encoded())

        let mockDelegate = MockSessionDelegate()
        let handler = FileRangeCommandHandler()
        _ = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer,
            delegate: mockDelegate
        )

        // Delegate should have been called with fileName, bytesInChunk=200, totalOffset=300 (100+200)
        XCTAssertEqual(mockDelegate.fileChunkEvents.count, 1)
        let event = mockDelegate.fileChunkEvents[0]
        XCTAssertEqual(event.fileName, "game.nsp")
        XCTAssertEqual(event.bytesInChunk, 200)
        XCTAssertEqual(event.totalOffset, 300) // offset 100 + 200 bytes sent
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
