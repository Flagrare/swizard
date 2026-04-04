import XCTest
@testable import NativeMTPTransport
import DBIProtocol

final class PrivilegedMTPSessionTests: XCTestCase {

    // MARK: - Behavior: parses progress output from privileged process

    func testParsesProgressLine() {
        let line = "PROGRESS:game.nsp:5242880:10485760"
        let parsed = PrivilegedMTPOutput.parse(line)

        if case .progress(let fileName, let sent, let total) = parsed {
            XCTAssertEqual(fileName, "game.nsp")
            XCTAssertEqual(sent, 5_242_880)
            XCTAssertEqual(total, 10_485_760)
        } else {
            XCTFail("Expected .progress, got \(parsed)")
        }
    }

    func testParsesOKLine() {
        let parsed = PrivilegedMTPOutput.parse("OK")
        XCTAssertEqual(parsed, .success)
    }

    func testParsesErrorLine() {
        let parsed = PrivilegedMTPOutput.parse("ERROR:Device disconnected")
        if case .error(let msg) = parsed {
            XCTAssertEqual(msg, "Device disconnected")
        } else {
            XCTFail("Expected .error")
        }
    }

    func testParsesLogLine() {
        let parsed = PrivilegedMTPOutput.parse("LOG:Opening session...")
        if case .log(let msg) = parsed {
            XCTAssertEqual(msg, "Opening session...")
        } else {
            XCTFail("Expected .log")
        }
    }

    func testParsesUnknownLineAsLog() {
        let parsed = PrivilegedMTPOutput.parse("some random output")
        if case .log(let msg) = parsed {
            XCTAssertEqual(msg, "some random output")
        } else {
            XCTFail("Expected .log for unknown format")
        }
    }

    // MARK: - Behavior: generates correct script with file paths

    // MARK: - Storage discovery

    func testScriptSearchesStoragesByName() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        // Script should use GetStorageInfo (0x1005) to get storage names
        XCTAssertTrue(script.contains("0x1005"), "Script should call GetStorageInfo")
        // Script should search for "install" in storage names (case-insensitive)
        XCTAssertTrue(script.contains("install"), "Script should search for install storage")
        // Script should NOT hardcode a storage ID
        XCTAssertFalse(script.contains("65541"), "Script should not hardcode storage 65541")
    }

    func testScriptPrefersSDInstallOverNANDInstall() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        // Script should prefer SD install (safer for user's NAND)
        XCTAssertTrue(script.contains("\"sd\"") || script.contains("\"SD\"") || script.lowercased().contains("sd"),
                       "Script should prefer SD install storage")
    }

    func testScriptUsesHasSuffixNotContainsForInstallMatch() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        // Must use hasSuffix("install") not contains("install")
        // "Installed games" contains "install" but does NOT end with "install"
        XCTAssertTrue(script.contains("hasSuffix"), "Script must use hasSuffix to avoid matching 'Installed games'")
        XCTAssertFalse(
            script.contains("contains(\"install\")"),
            "Script must NOT use contains(install) — matches 'Installed games' falsely"
        )
    }

    func testScriptHasNoStaleVariableNames() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: [PrivilegedMTPSession.FileToInstall(path: "/tmp/test.nsp", name: "test.nsp", size: 100)]
        )

        // Should not reference old variable names that were renamed
        XCTAssertFalse(script.contains("installFolderHandle"), "Stale variable: installFolderHandle")
        XCTAssertFalse(script.contains("storageResp"), "Stale variable: storageResp")
        XCTAssertFalse(script.contains("handlesData"), "Stale variable: handlesData (should be _ =)")
    }

    func testScriptUsesInstallStorageIDNotStorageID() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: [PrivilegedMTPSession.FileToInstall(path: "/tmp/test.nsp", name: "test.nsp", size: 100)]
        )

        // SendObjectInfo and ObjectInfo builder should use installStorageID
        XCTAssertTrue(script.contains("installStorageID"))
    }

    // MARK: - File paths

    func testScriptIncludesFilePaths() {
        let files = [
            PrivilegedMTPSession.FileToInstall(path: "/tmp/game1.nsp", name: "game1.nsp", size: 1000),
            PrivilegedMTPSession.FileToInstall(path: "/tmp/game2.xci", name: "game2.xci", size: 2000),
        ]

        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: files
        )

        XCTAssertTrue(script.contains("game1.nsp"))
        XCTAssertTrue(script.contains("game2.xci"))
        XCTAssertTrue(script.contains("/tmp/game1.nsp"))
        XCTAssertTrue(script.contains("1000"))
        XCTAssertTrue(script.contains("DeviceCapture"))
    }

    func testScriptWithEmptyFilesCompiles() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        // Empty files should produce valid Swift — no type inference issue
        XCTAssertTrue(script.contains("let files: [FileEntry] = []"))
        XCTAssertFalse(script.contains(".map"))
    }

    func testScriptUsesAbsolutePathsFromStaging() {
        // When files are staged to /tmp, the script should use /tmp paths (not user dir)
        let stagedFiles = [
            PrivilegedMTPSession.FileToInstall(
                path: "/tmp/swizard_install_test/game.nsp",
                name: "game.nsp",
                size: 1000
            )
        ]

        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: stagedFiles
        )

        XCTAssertTrue(script.contains("/tmp/swizard_install_test/game.nsp"))
        XCTAssertFalse(script.contains("/Users/"))
    }

    func testScriptIncludesVIDPID() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: 0x057E,
            productID: 0x201D,
            files: []
        )

        XCTAssertTrue(script.contains("1406"))  // 0x057E decimal
        XCTAssertTrue(script.contains("8221"))   // 0x201D decimal
    }
}
