import XCTest
@testable import DBIProtocol

/// Tests multi-file installation: the Switch installs 2 files in sequence.
final class MultiFileSessionTests: XCTestCase {

    func testTwoFileInstallation() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        let delegate = MockSessionDelegate()

        let file1 = Data(repeating: 0xAA, count: 128)
        let file2 = Data(repeating: 0xBB, count: 256)
        fileServer.register(name: "game1.nsp", content: file1)
        fileServer.register(name: "game2.xci", content: file2)

        // LIST
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .list, dataSize: 0))
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .list, dataSize: 0))

        // FILE_RANGE for game1.nsp (full file)
        let name1 = Data("game1.nsp".utf8)
        var payload1 = Data()
        payload1.appendLittleEndian(UInt32(128))
        payload1.appendLittleEndian(UInt64(0))
        payload1.appendLittleEndian(UInt32(name1.count))
        payload1.append(name1)
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload1.count)))
        transport.queueRead(payload1)
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // FILE_RANGE for game2.xci (full file)
        let name2 = Data("game2.xci".utf8)
        var payload2 = Data()
        payload2.appendLittleEndian(UInt32(256))
        payload2.appendLittleEndian(UInt64(0))
        payload2.appendLittleEndian(UInt32(name2.count))
        payload2.append(name2)
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload2.count)))
        transport.queueRead(payload2)
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: 0))

        // EXIT
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .exit, dataSize: 0))

        let session = DBISession()
        session.delegate = delegate
        try await session.run(transport: transport, fileServer: fileServer)

        // Should have 2 file chunk events, one per file
        XCTAssertEqual(delegate.fileChunkEvents.count, 2)
        XCTAssertEqual(delegate.fileChunkEvents[0].fileName, "game1.nsp")
        XCTAssertEqual(delegate.fileChunkEvents[0].totalOffset, 128)
        XCTAssertEqual(delegate.fileChunkEvents[1].fileName, "game2.xci")
        XCTAssertEqual(delegate.fileChunkEvents[1].totalOffset, 256)
        XCTAssertTrue(delegate.exitReceived)
    }

    func testFileRangeForMissingFilePropagatesToSession() async throws {
        let transport = MockTransport()
        let fileServer = MockFileServer()
        // Register NO files, but Switch requests one

        // LIST (returns empty)
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .list, dataSize: 0))
        transport.queueReadHeader(DBIHeader(commandType: .ack, commandID: .list, dataSize: 0))

        // FILE_RANGE for a file that doesn't exist
        let name = Data("missing.nsp".utf8)
        var payload = Data()
        payload.appendLittleEndian(UInt32(100))
        payload.appendLittleEndian(UInt64(0))
        payload.appendLittleEndian(UInt32(name.count))
        payload.append(name)
        transport.queueReadHeader(DBIHeader(commandType: .request, commandID: .fileRange, dataSize: UInt32(payload.count)))
        transport.queueRead(payload)

        let session = DBISession()

        do {
            try await session.run(transport: transport, fileServer: fileServer)
            XCTFail("Should have thrown for missing file")
        } catch {
            // Error should propagate — the session doesn't swallow it
            XCTAssertTrue(true)
        }
    }
}
