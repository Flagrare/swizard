import XCTest
@testable import DBIProtocol

final class ListCommandHandlerTests: XCTestCase {

    func testListCommandSendsFileListWithCorrectProtocolSequence() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        fileServer.register(name: "game1.nsp", content: Data(repeating: 0xAA, count: 100))
        fileServer.register(name: "game2.xci", content: Data(repeating: 0xBB, count: 200))

        let requestHeader = DBIHeader(commandType: .request, commandID: .list, dataSize: 0)
        transport.queueRead(DBIHeader(commandType: .ack, commandID: .list, dataSize: 0).encoded())

        let handler = ListCommandHandler()

        let result = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer,
            delegate: nil
        )

        XCTAssertEqual(result, .continue)
        XCTAssertEqual(transport.writtenData.count, 2)

        let responseHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(responseHeader.commandType, .response)
        XCTAssertEqual(responseHeader.commandID, .list)

        let fileListData = transport.writtenData[1]
        let fileList = String(data: fileListData, encoding: .utf8)
        XCTAssertEqual(fileList, "game1.nsp\ngame2.xci\n")
        XCTAssertEqual(responseHeader.dataSize, UInt32(fileListData.count))
    }

    func testListCommandWithEmptyFileListSendsZeroSizeResponse() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        let requestHeader = DBIHeader(commandType: .request, commandID: .list, dataSize: 0)
        transport.queueRead(DBIHeader(commandType: .ack, commandID: .list, dataSize: 0).encoded())

        let handler = ListCommandHandler()
        _ = try await handler.handle(
            header: requestHeader,
            transport: transport,
            fileServer: fileServer,
            delegate: nil
        )

        let responseHeader = try transport.writtenHeader(at: 0)
        XCTAssertEqual(responseHeader.dataSize, 0)
        XCTAssertEqual(transport.writtenData[1].count, 0)
    }

    func testListCommandIDIsCorrect() {
        let handler = ListCommandHandler()
        XCTAssertEqual(handler.commandID, .list)
    }
}
