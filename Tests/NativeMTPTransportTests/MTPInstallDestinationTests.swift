import XCTest
@testable import NativeMTPTransport
import DBIProtocol

final class MTPInstallDestinationTests: XCTestCase {

    // MARK: - Parsing install destinations from storage list

    func testFiltersOnlyInstallStorages() {
        let storages = [
            MTPStorageInfo(id: 65537, name: "1: SD Card"),
            MTPStorageInfo(id: 65540, name: "4: Installed games"),
            MTPStorageInfo(id: 65541, name: "5: SD Card install"),
            MTPStorageInfo(id: 65542, name: "6: NAND install"),
            MTPStorageInfo(id: 65544, name: "8: Album"),
        ]

        let destinations = MTPInstallDestination.fromStorages(storages)

        XCTAssertEqual(destinations.count, 2)
        XCTAssertEqual(destinations[0].storageID, 65541)
        XCTAssertEqual(destinations[1].storageID, 65542)
    }

    func testDefaultsToSDInstall() {
        let storages = [
            MTPStorageInfo(id: 65541, name: "5: SD Card install"),
            MTPStorageInfo(id: 65542, name: "6: NAND install"),
        ]

        let destinations = MTPInstallDestination.fromStorages(storages)
        let defaultDest = MTPInstallDestination.defaultDestination(from: destinations)

        XCTAssertEqual(defaultDest?.storageID, 65541)
    }

    func testFallsBackToNANDIfNoSD() {
        let storages = [
            MTPStorageInfo(id: 65542, name: "6: NAND install"),
        ]

        let destinations = MTPInstallDestination.fromStorages(storages)
        let defaultDest = MTPInstallDestination.defaultDestination(from: destinations)

        XCTAssertEqual(defaultDest?.storageID, 65542)
    }

    func testReturnsNilIfNoInstallStorages() {
        let storages = [
            MTPStorageInfo(id: 65537, name: "1: SD Card"),
            MTPStorageInfo(id: 65540, name: "4: Installed games"),
        ]

        let destinations = MTPInstallDestination.fromStorages(storages)
        XCTAssertTrue(destinations.isEmpty)

        let defaultDest = MTPInstallDestination.defaultDestination(from: destinations)
        XCTAssertNil(defaultDest)
    }

    func testCaseInsensitiveMatching() {
        let storages = [
            MTPStorageInfo(id: 100, name: "sd card INSTALL"),
            MTPStorageInfo(id: 200, name: "NAND INSTALL"),
        ]

        let destinations = MTPInstallDestination.fromStorages(storages)
        XCTAssertEqual(destinations.count, 2)
    }

    func testDisplayNameStripsPrefix() {
        let dest = MTPInstallDestination(storageID: 65541, rawName: "5: SD Card install")
        XCTAssertEqual(dest.displayName, "SD Card install")

        let dest2 = MTPInstallDestination(storageID: 65542, rawName: "6: NAND install")
        XCTAssertEqual(dest2.displayName, "NAND install")

        let dest3 = MTPInstallDestination(storageID: 100, rawName: "SD install")
        XCTAssertEqual(dest3.displayName, "SD install")
    }

    func testIsSDInstall() {
        let sd = MTPInstallDestination(storageID: 65541, rawName: "5: SD Card install")
        XCTAssertTrue(sd.isSDInstall)

        let nand = MTPInstallDestination(storageID: 65542, rawName: "6: NAND install")
        XCTAssertFalse(nand.isSDInstall)
    }
}
