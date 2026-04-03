import XCTest
@testable import DBIProtocol

final class ListCommandHandlerTests: XCTestCase {

    func testListCommandSendsFileListWithCorrectProtocolSequence() async throws {
        // Arrange: Switch sends LIST request, we have 2 files registered
        let transport = MockTransport()
        let fileServer = MockFileServer()
        fileServer.register(name: "game1.nsp", content: Data(repeating: 0xAA, count: 100))
        fileServer.register(name: "game2.xci", content: Data(repeating: 0xBB, count: 200))

        let requestHeader = DBIHeader(commandType: .request, commandID: .list, dataSize: 0)

        // The Switch will send an ACK after we send our RESPONSE header
        let ackHeader = DBIHeader(commandType: .ack, commandID: .list, dataSize: 0)
        transport.queueRead(ackHeader.encoded())

        let handler = ListCommandHandler()

        // Act
        let result = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer
        )

        // Assert: should continue (not exit)
        XCTAssertEqual(result, .continue)

        // Assert: handler wrote exactly 2 things — RESPONSE header, then file list bytes
        XCTAssertEqual(transport.writtenData.count, 2)

        // First write: RESPONSE header with file list size
        let responseHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(responseHeader.commandType, .response)
        XCTAssertEqual(responseHeader.commandID, .list)

        // Second write: the actual file list (newline-separated, sorted)
        let fileListData = transport.writtenData[1]
        let fileList = String(data: fileListData, encoding: .utf8)
        XCTAssertEqual(fileList, "game1.nsp\ngame2.xci\n")

        // The data size in the header should match the file list bytes
        XCTAssertEqual(responseHeader.dataSize, UInt32(fileListData.count))
    }

    func testListCommandWithEmptyFileListSendsZeroSizeResponse() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        let requestHeader = DBIHeader(commandType: .request, commandID: .list, dataSize: 0)
        let ackHeader = DBIHeader(commandType: .ack, commandID: .list, dataSize: 0)
        transport.queueRead(ackHeader.encoded())

        let handler = ListCommandHandler()
        _ = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer
        )

        let responseHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(responseHeader.dataSize, 0)

        // With empty list, second write should be empty
        XCTAssertEqual(transport.writtenData[1].count, 0)
    }

    func testListCommandIDIsCorrect() {
        let handler = ListCommandHandler()
        XCTAssertEqual(handler.commandID, .list)
    }
}
