import XCTest
@testable import MTPTransport

final class MTPDeviceTests: XCTestCase {

    // MARK: - MTPRawDevice Value Object

    func testRawDeviceEquality() {
        let a = MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: 0x057E, productId: 0x3000)
        let b = MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: 0x057E, productId: 0x3000)
        XCTAssertEqual(a, b)
    }

    func testRawDeviceInequality() {
        let a = MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: 0x057E, productId: 0x3000)
        let b = MTPRawDevice(busNumber: 1, deviceNumber: 3, vendorId: 0x057E, productId: 0x3000)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - MTPStorage Value Object

    func testStorageProperties() {
        let storage = MTPStorage(id: 1, description: "MicroSD", freeSpaceInBytes: 32_000_000_000, maxCapacity: 64_000_000_000)
        XCTAssertEqual(storage.id, 1)
        XCTAssertEqual(storage.description, "MicroSD")
        XCTAssertEqual(storage.freeSpaceInBytes, 32_000_000_000)
    }

    // MARK: - MTPFolder Value Object

    func testFolderProperties() {
        let folder = MTPFolder(id: 10, parentId: 0, storageId: 1, name: "MicroSD Install")
        XCTAssertEqual(folder.id, 10)
        XCTAssertEqual(folder.name, "MicroSD Install")
        XCTAssertEqual(folder.parentId, 0)
    }

    // MARK: - MTPError

    func testTransferFailedIsRetryable() {
        XCTAssertTrue(MTPError.transferFailed("timeout").isRetryable)
    }

    func testDeviceNotFoundIsNotRetryable() {
        XCTAssertFalse(MTPError.deviceNotFound.isRetryable)
    }

    func testCancelledIsNotRetryable() {
        XCTAssertFalse(MTPError.cancelled.isRetryable)
    }

    // MARK: - MockMTPDevice Protocol Conformance

    func testMockDetectsDevices() async throws {
        let mock = MockMTPDevice()
        mock.devicesToReturn = [
            MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: 0x057E, productId: 0x3000)
        ]

        let devices = try await mock.detectDevices()
        XCTAssertEqual(devices.count, 1)
        XCTAssertEqual(devices[0].vendorId, 0x057E)
        XCTAssertTrue(mock.detectCalled)
    }

    func testMockThrowsWhenNoDevices() async {
        let mock = MockMTPDevice()

        do {
            _ = try await mock.detectDevices()
            XCTFail("Should have thrown")
        } catch let error as MTPError {
            XCTAssertEqual(error, .deviceNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockOpenCloseLifecycle() async throws {
        let mock = MockMTPDevice()
        let device = MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: 0x057E, productId: 0x3000)

        try await mock.open(device: device)
        XCTAssertEqual(mock.openedDevice, device)

        await mock.close()
        XCTAssertTrue(mock.closeCalled)
    }

    func testMockSendFileRecordsCall() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 1000, maxCapacity: 2000)]

        try await mock.sendFile(
            localPath: "/tmp/game.nsp",
            fileName: "game.nsp",
            fileSize: 1000,
            parentFolderId: 10,
            storageId: 1,
            progress: { _, _ in true }
        )

        XCTAssertEqual(mock.sentFiles.count, 1)
        XCTAssertEqual(mock.sentFiles[0].fileName, "game.nsp")
        XCTAssertEqual(mock.sentFiles[0].parentFolderId, 10)
        XCTAssertEqual(mock.progressCallCount, 3) // 0%, 50%, 100%
    }
}
