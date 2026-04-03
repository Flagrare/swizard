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

        // 1. Switch sends CMD_LIST request
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .list, dataSize: 0))
        // 2. Switch ACKs our LIST response
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
        // 5. Switch ACKs our FILE_RANGE response
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // 6. Switch sends CMD_EXIT
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        let session = DBISession()
        try await session.run(transport: transport, fileServer: fileServer)

        // Write 0: LIST response header
        let listResponse = try transport.writtenHeader(at: 0)
        XCTAssertEqual(listResponse.commandType, .response)
        XCTAssertEqual(listResponse.commandID, .list)

        // Write 1: file list bytes (with trailing newline)
        let fileList = String(data: transport.writtenData[1], encoding: .utf8)
        XCTAssertEqual(fileList, "game.nsp\n")

        // Write 2: FILE_RANGE ACK header
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

    func testSessionDelegateReceivesLogMessages() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let delegate = MockSessionDelegate()

        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        let session = DBISession()
        session.delegate = delegate
        try await session.run(transport: transport, fileServer: fileServer)

        // Should have logged: "DBI session started", "Received exit (request)", "DBI session ended"
        XCTAssertTrue(delegate.logMessages.contains(where: { $0.contains("session started") }))
        XCTAssertTrue(delegate.logMessages.contains(where: { $0.contains("session ended") }))
        XCTAssertTrue(delegate.exitReceived)
    }

    func testSessionDelegateReceivesProgressOnFileRange() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let delegate = MockSessionDelegate()
        fileServer.register(name: "game.nsp", content: Data(repeating: 0x00, count: 1024))

        let fileName = "game.nsp"
        let fileNameData = Data(fileName.utf8)

        // LIST
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .list, dataSize: 0))
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .list, dataSize: 0))

        // FILE_RANGE: 512 bytes at offset 0
        var payload1 = Data()
        payload1.appendLittleEndian(UInt32(512))
        payload1.appendLittleEndian(UInt64(0))
        payload1.appendLittleEndian(UInt32(fileNameData.count))
        payload1.append(fileNameData)
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload1.count)))
        transport.queueRead(payload1)
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // FILE_RANGE: 512 bytes at offset 512
        var payload2 = Data()
        payload2.appendLittleEndian(UInt32(512))
        payload2.appendLittleEndian(UInt64(512))
        payload2.appendLittleEndian(UInt32(fileNameData.count))
        payload2.append(fileNameData)
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload2.count)))
        transport.queueRead(payload2)
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // EXIT
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        let session = DBISession()
        session.delegate = delegate
        try await session.run(transport: transport, fileServer: fileServer)

        // Delegate should have received 2 file chunk events
        XCTAssertEqual(delegate.fileChunkEvents.count, 2)

        // First chunk: 512 bytes at offset 0 → totalOffset = 512
        XCTAssertEqual(delegate.fileChunkEvents[0].fileName, "game.nsp")
        XCTAssertEqual(delegate.fileChunkEvents[0].bytesInChunk, 512)
        XCTAssertEqual(delegate.fileChunkEvents[0].totalOffset, 512)

        // Second chunk: 512 bytes at offset 512 → totalOffset = 1024
        XCTAssertEqual(delegate.fileChunkEvents[1].fileName, "game.nsp")
        XCTAssertEqual(delegate.fileChunkEvents[1].bytesInChunk, 512)
        XCTAssertEqual(delegate.fileChunkEvents[1].totalOffset, 1024)
    }

    func testSessionThrowsOnUnknownCommand() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()

        // Craft a header with an unknown command ID
        var data = Data("DBI0".utf8)
        data.appendLittleEndian(UInt32(0)) // REQUEST
        data.appendLittleEndian(UInt32(99)) // unknown command
        data.appendLittleEndian(UInt32(0))

        transport.queueRead(data)

        let session = DBISession()
        do {
            try await session.run(transport: transport, fileServer: fileServer)
            XCTFail("Should have thrown")
        } catch let error as DBIError {
            if case .unknownCommand(99) = error { } else {
                XCTFail("Expected .unknownCommand(99), got \(error)")
            }
        }
    }
}
