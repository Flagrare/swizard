import XCTest
@testable import DBIProtocol

final class ExitCommandHandlerTests: XCTestCase {

    func testExitCommandSendsResponseAndReturnsExit() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let header = DBIHeader(commandType: .request, commandID: .exit, dataSize: 0)

        let handler = ExitCommandHandler()
        let result = try await handler.handle(
            header: header,
            transport: transport,
            fileServer: fileServer,
            delegate: nil
        )

        XCTAssertEqual(result, .exit)
        XCTAssertEqual(transport.writtenData.count, 1)

        let response = try transport.writtenHeader(at: 0)
        XCTAssertEqual(response.commandType, .response)
        XCTAssertEqual(response.commandID, .exit)
        XCTAssertEqual(response.dataSize, 0)
    }

    func testExitCommandIDIsCorrect() {
        let handler = ExitCommandHandler()
        XCTAssertEqual(handler.commandID, .exit)
    }
}
