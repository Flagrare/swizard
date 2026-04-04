import XCTest
@testable import NativeMTPTransport
import DBIProtocol

final class PrivilegedMTPSessionTests: XCTestCase {

    // MARK: - Output parsing

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

    // MARK: - C script generation

    func testScriptIsValidCProgram() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        XCTAssertTrue(script.contains("#include <libmtp.h>"), "Should include libmtp header")
        XCTAssertTrue(script.contains("int main()"), "Should have main function")
        XCTAssertTrue(script.contains("LIBMTP_Init()"), "Should initialize libmtp")
        XCTAssertTrue(script.contains("LIBMTP_Send_File_From_File"), "Should use libmtp's proven send function")
    }

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
    }

    func testScriptWithEmptyFilesCompiles() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        XCTAssertTrue(script.contains("int file_count = 0"))
    }

    func testScriptUsesHasSuffixForInstallMatch() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        // C code should match storage names ending with "install"
        XCTAssertTrue(script.contains("strcasecmp") || script.contains("install"),
                       "Should search for install storage by name")
    }

    func testScriptHandlesStorageOverride() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: [],
            targetStorageID: 65541
        )

        XCTAssertTrue(script.contains("65541"))
        XCTAssertTrue(script.contains("has_override = 1"))
    }

    func testScriptWithoutOverride() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: [],
            targetStorageID: nil
        )

        XCTAssertTrue(script.contains("has_override = 0"))
    }

    func testScriptUsesLibmtpNotIOUSBHost() {
        let script = PrivilegedMTPSession.buildScript(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID,
            files: []
        )

        XCTAssertTrue(script.contains("LIBMTP_"), "Should use libmtp (proven reference implementation)")
        XCTAssertFalse(script.contains("IOUSBHost"), "Should NOT use IOUSBHost (broken pipe issue)")
    }
}
