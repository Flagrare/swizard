import XCTest
@testable import DBIProtocol

final class DBISessionTests: XCTestCase {

    /// Scripts a complete DBI conversation: LIST → FILE_RANGE → EXIT
    func testFullInstallationConversation() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let fileContent = Data(repeating: 0xAB, count: 256)
        fileServer.register(name: "game.nsp", content: fileContent)

        let fileName = "game.nsp"
        let fileNameData = Data(fileName.utf8)

        // Script the Switch side of the conversation:

        // 1. Switch sends CMD_LIST request
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .list, dataSize: 0))

        // 2. Switch sends ACK after receiving our LIST response header
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .list, dataSize: 0))

        // 3. Switch sends CMD_FILE_RANGE request
        var rangePayload = Data()
        rangePayload.appendLittleEndian(UInt32(256))              // rangeSize
        rangePayload.appendLittleEndian(UInt64(0))                // rangeOffset
        rangePayload.appendLittleEndian(UInt32(fileNameData.count))
        rangePayload.append(fileNameData)

        transport.queueReadHeader(DBIHeader(
            commandType: .request,
            commandID: .fileRange,
            dataSize: UInt32(rangePayload.count)
        ))
        transport.queueRead(rangePayload)

        // 4. Switch sends ACK after receiving our FILE_RANGE response header
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // 5. Switch sends CMD_EXIT
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        // Run the session
        let session = DBISession()
        try await session.run(transport: transport, fileServer: fileServer)

        // Verify the Mac sent the right responses:
        // Write 0: LIST response header
        let listResponse = try transport.writtenHeader(at: 0)
        XCTAssertEqual(listResponse.commandType, .response)
        XCTAssertEqual(listResponse.commandID, .list)

        // Write 1: file list bytes
        let fileList = String(data: transport.writtenData[1], encoding: .utf8)
        XCTAssertEqual(fileList, "game.nsp")

        // Write 2: FILE_RANGE response header
        let rangeResponse = try transport.writtenHeader(at: 2)
        XCTAssertEqual(rangeResponse.commandType, .response)
        XCTAssertEqual(rangeResponse.commandID, .fileRange)
        XCTAssertEqual(rangeResponse.dataSize, 256)

        // Write 3: file data
        XCTAssertEqual(transport.writtenData[3], fileContent)

        // Write 4: EXIT response header
        let exitResponse = try transport.writtenHeader(at: 4)
        XCTAssertEqual(exitResponse.commandType, .response)
        XCTAssertEqual(exitResponse.commandID, .exit)
    }

    /// Session should stop after receiving EXIT command.
    func testSessionStopsOnExit() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        // Just send EXIT immediately
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        let session = DBISession()
        try await session.run(transport: transport, fileServer: fileServer)

        // Should have written exactly 1 response (the EXIT response)
        XCTAssertEqual(transport.writtenData.count, 1)
    }
}
