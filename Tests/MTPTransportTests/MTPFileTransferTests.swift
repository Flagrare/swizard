import XCTest
@testable import MTPTransport

final class MTPFileTransferTests: XCTestCase {

    func testTransferSendsFileToCorrectFolder() async throws {
        let mock = MockMTPDevice()
        let transfer = MTPFileTransfer(device: mock)

        try await transfer.sendFile(
            localPath: "/tmp/game.nsp",
            fileName: "game.nsp",
            fileSize: 10_000,
            parentFolderId: 42,
            storageId: 1,
            progress: { _, _ in true }
        )

        XCTAssertEqual(mock.sentFiles.count, 1)
        XCTAssertEqual(mock.sentFiles[0].fileName, "game.nsp")
        XCTAssertEqual(mock.sentFiles[0].localPath, "/tmp/game.nsp")
        XCTAssertEqual(mock.sentFiles[0].parentFolderId, 42)
        XCTAssertEqual(mock.sentFiles[0].storageId, 1)
    }

    func testTransferReportsProgressToCallback() async throws {
        let mock = MockMTPDevice()
        let transfer = MTPFileTransfer(device: mock)

        let collector = ProgressCollector()

        try await transfer.sendFile(
            localPath: "/tmp/game.nsp",
            fileName: "game.nsp",
            fileSize: 10_000,
            parentFolderId: 1,
            storageId: 1,
            progress: { sent, total in
                collector.add(sent: sent, total: total)
                return true
            }
        )

        let updates = collector.updates
        XCTAssertEqual(updates.count, 3)
        XCTAssertEqual(updates[0].sent, 0)
        XCTAssertEqual(updates[1].sent, 5_000)
        XCTAssertEqual(updates[2].sent, 10_000)
        XCTAssertEqual(updates[2].total, 10_000)
    }

    func testTransferPropagatesDeviceError() async {
        let mock = MockMTPDevice()
        mock.sendFileError = .transferFailed("timeout")
        let transfer = MTPFileTransfer(device: mock)

        do {
            try await transfer.sendFile(
                localPath: "/tmp/fail.nsp",
                fileName: "fail.nsp",
                fileSize: 1000,
                parentFolderId: 1,
                storageId: 1,
                progress: { _, _ in true }
            )
            XCTFail("Should have thrown")
        } catch let error as MTPError {
            XCTAssertEqual(error, .transferFailed("timeout"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testTransferMultipleFilesSequentially() async throws {
        let mock = MockMTPDevice()
        let transfer = MTPFileTransfer(device: mock)

        try await transfer.sendFile(
            localPath: "/tmp/game1.nsp", fileName: "game1.nsp",
            fileSize: 1000, parentFolderId: 10, storageId: 1,
            progress: { _, _ in true }
        )
        try await transfer.sendFile(
            localPath: "/tmp/game2.xci", fileName: "game2.xci",
            fileSize: 2000, parentFolderId: 10, storageId: 1,
            progress: { _, _ in true }
        )

        XCTAssertEqual(mock.sentFiles.count, 2)
        XCTAssertEqual(mock.sentFiles[0].fileName, "game1.nsp")
        XCTAssertEqual(mock.sentFiles[1].fileName, "game2.xci")
    }
}

/// Thread-safe progress collector for @Sendable closure tests.
private final class ProgressCollector: @unchecked Sendable {
    struct Update { let sent: UInt64; let total: UInt64 }
    private(set) var updates: [Update] = []

    func add(sent: UInt64, total: UInt64) {
        updates.append(Update(sent: sent, total: total))
    }
}
