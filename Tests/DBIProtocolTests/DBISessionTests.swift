import XCTest
@testable import DBIProtocol

final class DBISessionTests: XCTestCase {

    /// Scripts a complete DBI conversation: LIST → FILE_RANGE → EXIT
    /// Verifies the exact protocol sequence including ACKs.
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
        rangePayload.appendLittleEndian(UInt32(256))
        rangePayload.appendLittleEndian(UInt64(0))
        rangePayload.appendLittleEndian(UInt32(fileNameData.count))
        rangePayload.append(fileNameData)

        transport.queueReadHeader(DBIHeader(
            commandType: .request,
            commandID: .fileRange,
            dataSize: UInt32(rangePayload.count)
        ))

        // 4. After our ACK, Switch sends the payload
        transport.queueRead(rangePayload)

        // 5. Switch sends ACK after receiving our FILE_RANGE response header
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // 6. Switch sends CMD_EXIT
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        // Run the session
        let session = DBISession()
        try await session.run(transport: transport, fileServer: fileServer)

        // Verify the Mac sent the right responses:
        // Write 0: LIST response header
        let listResponse = try transport.writtenHeader(at: 0)
        XCTAssertEqual(listResponse.commandType, .response)
        XCTAssertEqual(listResponse.commandID, .list)

        // Write 1: file list bytes (with trailing newline per DBI spec)
        let fileList = String(data: transport.writtenData[1], encoding: .utf8)
        XCTAssertEqual(fileList, "game.nsp\n")

        // Write 2: FILE_RANGE ACK header (acknowledging the request)
        let rangeAck = try transport.writtenHeader(at: 2)
        XCTAssertEqual(rangeAck.commandType, .ack)
        XCTAssertEqual(rangeAck.commandID, .fileRange)

        // Write 3: FILE_RANGE response header
        let rangeResponse = try transport.writtenHeader(at: 3)
        XCTAssertEqual(rangeResponse.commandType, .response)
        XCTAssertEqual(rangeResponse.commandID, .fileRange)
        XCTAssertEqual(rangeResponse.dataSize, 256)

        // Write 4: file data
        XCTAssertEqual(transport.writtenData[4], fileContent)

        // Write 5: EXIT response header
        let exitResponse = try transport.writtenHeader(at: 5)
        XCTAssertEqual(exitResponse.commandType, .response)
        XCTAssertEqual(exitResponse.commandID, .exit)
    }

    func testSessionStopsOnExit() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        let session = DBISession()
        try await session.run(transport: transport, fileServer: fileServer)

        XCTAssertEqual(transport.writtenData.count, 1)
    }
}
