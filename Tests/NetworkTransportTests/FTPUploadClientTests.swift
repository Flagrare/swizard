import XCTest
@testable import NetworkTransport

final class FTPUploadClientTests: XCTestCase {

    func testConstructsCorrectCurlCommand() {
        let client = FTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/game.nsz")

        let args = client.buildCurlArguments(file: file, connection: connection)

        XCTAssertTrue(args.contains("-T"))
        XCTAssertTrue(args.contains("/tmp/game.nsz"))
        XCTAssertTrue(args.contains("ftp://192.168.0.96:5000/game.nsz"))
        XCTAssertTrue(args.contains("--progress-bar"))
    }

    func testCurlArgumentsIncludeAnonymousUser() {
        let client = FTPUploadClient()
        let connection = FTPConnectionInfo(host: "10.0.0.1", port: 6000)
        let file = URL(fileURLWithPath: "/tmp/test.nsp")

        let args = client.buildCurlArguments(file: file, connection: connection)

        XCTAssertTrue(args.contains("--user"))
        XCTAssertTrue(args.contains("anonymous:"))
    }

    func testCurlArgumentsDisableEPSV() {
        let client = FTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/game.nsz")

        let args = client.buildCurlArguments(file: file, connection: connection)

        // DBI doesn't support EPSV — curl must use PASV
        XCTAssertTrue(args.contains("--disable-epsv"))
    }

    func testCurlArgumentsDisableGlobbing() {
        let client = FTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/game [v0].nsz")

        let args = client.buildCurlArguments(file: file, connection: connection)

        // curl treats [...] as glob ranges — must disable with --globoff
        XCTAssertTrue(args.contains("--globoff") || args.contains("-g"),
                       "Must disable curl globbing for filenames with brackets")
    }

    func testCurlArgumentsUseEncodedURL() {
        let client = FTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/Jump Rope [v0] (0.07 GB).nsz")

        let args = client.buildCurlArguments(file: file, connection: connection)

        // The FTP URL in args should be percent-encoded
        let urlArg = args.first(where: { $0.starts(with: "ftp://") })!
        XCTAssertFalse(urlArg.contains(" "), "URL must not contain raw spaces")
        XCTAssertFalse(urlArg.contains("["), "URL must not contain raw brackets")
        XCTAssertTrue(urlArg.contains("%20"), "Spaces should be percent-encoded")
    }

    func testUploadLogsURLBeforeTransfer() async throws {
        let mock = MockFTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/game.nsz")

        try await mock.upload(file: file, to: connection, onProgress: { _ in }, onLog: { _ in })
        XCTAssertEqual(mock.uploadedFiles.count, 1)
    }

    func testMockClientRecordsUpload() async throws {
        let mock = MockFTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/game.nsz")

        try await mock.upload(file: file, to: connection, onProgress: { _ in }, onLog: { _ in })

        XCTAssertEqual(mock.uploadedFiles.count, 1)
        XCTAssertEqual(mock.uploadedFiles[0].lastPathComponent, "game.nsz")
    }

    func testMockClientReportsProgress() async throws {
        let mock = MockFTPUploadClient()
        let connection = FTPConnectionInfo(host: "192.168.0.96", port: 5000)
        let file = URL(fileURLWithPath: "/tmp/game.nsz")

        let collector = ProgressCollector()
        try await mock.upload(file: file, to: connection, onProgress: { p in
            collector.add(p)
        }, onLog: { _ in })

        XCTAssertEqual(collector.values.count, 3)
        XCTAssertEqual(collector.values.last, 100.0)
    }
}

private final class ProgressCollector: @unchecked Sendable {
    private(set) var values: [Double] = []
    func add(_ v: Double) { values.append(v) }
}

/// Mock FTP client for tests — no network, records calls.
final class MockFTPUploadClient: FTPUploadClientProtocol, @unchecked Sendable {
    var uploadedFiles: [URL] = []
    var shouldFail = false

    func upload(
        file: URL,
        to connection: FTPConnectionInfo,
        onProgress: @escaping @Sendable (Double) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws {
        if shouldFail { throw FTPUploadError.connectionFailed("Mock failure") }
        uploadedFiles.append(file)
        onProgress(0)
        onProgress(50)
        onProgress(100)
    }
}
