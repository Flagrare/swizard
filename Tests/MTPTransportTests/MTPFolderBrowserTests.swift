import XCTest
@testable import MTPTransport

final class MTPFolderBrowserTests: XCTestCase {

    // MARK: - Storage enumeration

    func testBrowseReturnsStorages() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "MicroSD", freeSpaceInBytes: 32_000_000_000, maxCapacity: 64_000_000_000),
            MTPStorage(id: 2, description: "NAND", freeSpaceInBytes: 8_000_000_000, maxCapacity: 32_000_000_000),
        ]

        let browser = MTPFolderBrowser(device: mock)
        let storages = try await browser.getStorages()

        XCTAssertEqual(storages.count, 2)
        XCTAssertEqual(storages[0].description, "MicroSD")
        XCTAssertEqual(storages[1].description, "NAND")
    }

    // MARK: - Folder listing

    func testBrowseReturnsFoldersForStorage() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 1000, maxCapacity: 2000)
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 10, parentId: 0, storageId: 1, name: "MicroSD Install"),
            MTPFolder(id: 11, parentId: 0, storageId: 1, name: "NAND Install"),
            MTPFolder(id: 12, parentId: 0, storageId: 1, name: "SD Card"),
        ]

        let browser = MTPFolderBrowser(device: mock)
        let folders = try await browser.getFolders(storageId: 1)

        XCTAssertEqual(folders.count, 3)
        XCTAssertTrue(folders.contains(where: { $0.name == "MicroSD Install" }))
    }

    // MARK: - Find install folder

    func testFindInstallFolderByName() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 1000, maxCapacity: 2000)
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 10, parentId: 0, storageId: 1, name: "MicroSD Install"),
            MTPFolder(id: 11, parentId: 0, storageId: 1, name: "NAND Install"),
            MTPFolder(id: 12, parentId: 0, storageId: 1, name: "SD Card"),
        ]

        let browser = MTPFolderBrowser(device: mock)
        let folder = try await browser.findInstallFolder(named: "MicroSD Install", storageId: 1)

        XCTAssertNotNil(folder)
        XCTAssertEqual(folder?.id, 10)
        XCTAssertEqual(folder?.name, "MicroSD Install")
    }

    func testFindInstallFolderReturnsNilWhenNotFound() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 1000, maxCapacity: 2000)
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 12, parentId: 0, storageId: 1, name: "SD Card"),
        ]

        let browser = MTPFolderBrowser(device: mock)
        let folder = try await browser.findInstallFolder(named: "MicroSD Install", storageId: 1)

        XCTAssertNil(folder)
    }

    func testFindInstallFolderSearchesAcrossStorages() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "NAND", freeSpaceInBytes: 1000, maxCapacity: 2000),
            MTPStorage(id: 2, description: "SD", freeSpaceInBytes: 5000, maxCapacity: 10000),
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 20, parentId: 0, storageId: 2, name: "MicroSD Install"),
        ]

        let browser = MTPFolderBrowser(device: mock)
        let result = try await browser.findFirstInstallFolder(preferredName: "MicroSD Install")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.folder.id, 20)
        XCTAssertEqual(result?.storageId, 2)
    }

    func testFindFirstInstallFolderReturnsNilAcrossAllStorages() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "NAND", freeSpaceInBytes: 1000, maxCapacity: 2000),
        ]
        mock.foldersToReturn = []

        let browser = MTPFolderBrowser(device: mock)
        let result = try await browser.findFirstInstallFolder(preferredName: "MicroSD Install")

        XCTAssertNil(result)
    }

    // MARK: - Case-insensitive search

    func testFindInstallFolderIsCaseInsensitive() async throws {
        let mock = MockMTPDevice()
        mock.storagesToReturn = [
            MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 1000, maxCapacity: 2000)
        ]
        mock.foldersToReturn = [
            MTPFolder(id: 10, parentId: 0, storageId: 1, name: "microsd install"),
        ]

        let browser = MTPFolderBrowser(device: mock)
        let folder = try await browser.findInstallFolder(named: "MicroSD Install", storageId: 1)

        XCTAssertNotNil(folder)
        XCTAssertEqual(folder?.id, 10)
    }
}
