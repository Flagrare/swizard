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
