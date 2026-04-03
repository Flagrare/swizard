import XCTest
@testable import MTPTransport
import DBIProtocol

final class MTPInstallerTests: XCTestCase {

    private func makeConfiguredMock() -> MockMTPDevice {
        let mock = MockMTPDevice()
        mock.devicesToReturn = [
            MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: NintendoSwitchUSB.vendorID, productId: NintendoSwitchUSB.mtpProductID)
        ]
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 32_000_000_000, maxCapacity: 64_000_000_000)
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 10, parentId: 0, storageId: 1, name: "MicroSD Install"),
            MTPFolder(id: 11, parentId: 0, storageId: 1, name: "SD Card"),
        ]
        return mock
    }

    // MARK: - Happy path

    func testInstallSendsFilesToInstallFolder() async throws {
        let mock = makeConfiguredMock()
        let installer = MTPInstaller(device: mock)

        let collector = ProgressCollector()
        try await installer.install(
            files: [("/tmp/game.nsp", "game.nsp", UInt64(10_000))],
            progress: { fileName, sent, total in
                collector.add(fileName: fileName, sent: sent, total: total)
                return true
            }
        )

        XCTAssertTrue(mock.detectCalled)
        XCTAssertNotNil(mock.openedDevice)
        XCTAssertEqual(mock.sentFiles.count, 1)
        XCTAssertEqual(mock.sentFiles[0].fileName, "game.nsp")
        XCTAssertEqual(mock.sentFiles[0].parentFolderId, 10) // "MicroSD Install" folder
        XCTAssertTrue(mock.closeCalled)
    }

    func testInstallMultipleFiles() async throws {
        let mock = makeConfiguredMock()
        let installer = MTPInstaller(device: mock)

        try await installer.install(
            files: [
                ("/tmp/game1.nsp", "game1.nsp", UInt64(1000)),
                ("/tmp/game2.xci", "game2.xci", UInt64(2000)),
            ],
            progress: { _, _, _ in true }
        )

        XCTAssertEqual(mock.sentFiles.count, 2)
        XCTAssertEqual(mock.sentFiles[0].fileName, "game1.nsp")
        XCTAssertEqual(mock.sentFiles[1].fileName, "game2.xci")
    }

    // MARK: - Error cases

    func testInstallThrowsWhenNoDeviceFound() async {
        let mock = MockMTPDevice() // empty — no devices
        let installer = MTPInstaller(device: mock)

        do {
            try await installer.install(
                files: [("/tmp/game.nsp", "game.nsp", UInt64(1000))],
                progress: { _, _, _ in true }
            )
            XCTFail("Should have thrown")
        } catch let error as MTPError {
            XCTAssertEqual(error, .deviceNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallThrowsWhenInstallFolderNotFound() async {
        let mock = MockMTPDevice()
        mock.devicesToReturn = [
            MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: NintendoSwitchUSB.vendorID, productId: NintendoSwitchUSB.mtpProductID)
        ]
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 1000, maxCapacity: 2000)
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 12, parentId: 0, storageId: 1, name: "SD Card"), // No install folder
        ]

        let installer = MTPInstaller(device: mock)

        do {
            try await installer.install(
                files: [("/tmp/game.nsp", "game.nsp", UInt64(1000))],
                progress: { _, _, _ in true }
            )
            XCTFail("Should have thrown")
        } catch let error as MTPError {
            if case .installFolderNotFound = error { } else {
                XCTFail("Expected .installFolderNotFound, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testInstallClosesDeviceEvenOnError() async {
        let mock = makeConfiguredMock()
        mock.sendFileError = .transferFailed("disk full")
        let installer = MTPInstaller(device: mock)

        do {
            try await installer.install(
                files: [("/tmp/game.nsp", "game.nsp", UInt64(1000))],
                progress: { _, _, _ in true }
            )
        } catch {
            // Expected
        }

        // Device should still be closed even after error
        XCTAssertTrue(mock.closeCalled)
    }

    func testInstallReportsProgressWithFileName() async throws {
        let mock = makeConfiguredMock()
        let installer = MTPInstaller(device: mock)

        let collector = ProgressCollector()
        try await installer.install(
            files: [("/tmp/game.nsp", "game.nsp", UInt64(10_000))],
            progress: { fileName, sent, total in
                collector.add(fileName: fileName, sent: sent, total: total)
                return true
            }
        )

        XCTAssertFalse(collector.updates.isEmpty)
        XCTAssertTrue(collector.updates.allSatisfy { $0.fileName == "game.nsp" })
    }
}

/// Thread-safe progress collector.
private final class ProgressCollector: @unchecked Sendable {
    struct Update { let fileName: String; let sent: UInt64; let total: UInt64 }
    private(set) var updates: [Update] = []

    func add(fileName: String, sent: UInt64, total: UInt64) {
        updates.append(Update(fileName: fileName, sent: sent, total: total))
    }
}
