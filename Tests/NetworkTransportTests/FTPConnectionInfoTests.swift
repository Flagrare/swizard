import XCTest
@testable import NetworkTransport

final class FTPConnectionInfoTests: XCTestCase {

    // MARK: - URL construction

    func testConstructsFTPURLFromHostPortAndFilename() {
        let info = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let url = info.uploadURL(for: "game.nsz")

        XCTAssertEqual(url, "ftp://192.168.0.96:5000/game.nsz")
    }

    func testConstructsURLWithDifferentPort() {
        let info = FTPConnectionInfo(host: "10.0.0.5", port: 6000)
        let url = info.uploadURL(for: "update.nsp")

        XCTAssertEqual(url, "ftp://10.0.0.5:6000/update.nsp")
    }

    func testHandlesFilenameWithSpacesAndSpecialChars() {
        let info = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let url = info.uploadURL(for: "Jump Rope Challenge [0100B9C012706000][v0] (0.07 GB).nsz")

        XCTAssertTrue(url.starts(with: "ftp://192.168.0.96:5000/"))
        XCTAssertTrue(url.contains("Jump"))
    }

    // MARK: - Default port

    func testDefaultPortIs5000() {
        XCTAssertEqual(DBIFTPConstants.defaultPort, 5000)
    }

    // MARK: - Accepted extensions

    func testAcceptedExtensions() {
        XCTAssertTrue(DBIFTPConstants.acceptedExtensions.contains("nsp"))
        XCTAssertTrue(DBIFTPConstants.acceptedExtensions.contains("nsz"))
        XCTAssertTrue(DBIFTPConstants.acceptedExtensions.contains("xci"))
        XCTAssertTrue(DBIFTPConstants.acceptedExtensions.contains("xcz"))
    }

    // MARK: - Display string

    func testDisplayString() {
        let info = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        XCTAssertEqual(info.displayString, "192.168.0.96:5000")
    }

    // MARK: - Parsing from user input

    func testParsesHostColonPort() {
        let info = FTPConnectionInfo.parse("192.168.0.96:5000")
        XCTAssertEqual(info?.host, "192.168.0.96")
        XCTAssertEqual(info?.port, 5000)
    }

    func testParsesHostOnlyWithDefaultPort() {
        let info = FTPConnectionInfo.parse("192.168.0.96")
        XCTAssertEqual(info?.host, "192.168.0.96")
        XCTAssertEqual(info?.port, DBIFTPConstants.defaultPort)
    }

    func testRejectsEmptyString() {
        XCTAssertNil(FTPConnectionInfo.parse(""))
    }

    func testRejectsInvalidPort() {
        XCTAssertNil(FTPConnectionInfo.parse("192.168.0.96:abc"))
    }
}
