import XCTest
@testable import NetworkTransport

final class RangeRequestHandlerTests: XCTestCase {

    // MARK: - Range header parsing

    func testParsesSimpleRangeHeader() throws {
        let range = try HTTPRange.parse("bytes=0-99")
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 99)
    }

    func testParsesOpenEndedRange() throws {
        let range = try HTTPRange.parse("bytes=100-")
        XCTAssertEqual(range.start, 100)
        XCTAssertNil(range.end)
    }

    func testParsesLargeRange() throws {
        let range = try HTTPRange.parse("bytes=0-4294967295")
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 4_294_967_295)
    }

    func testRejectsInvalidRangeFormat() {
        XCTAssertThrowsError(try HTTPRange.parse("invalid"))
        XCTAssertThrowsError(try HTTPRange.parse("bytes=abc-def"))
        XCTAssertThrowsError(try HTTPRange.parse(""))
    }

    // MARK: - HTTP request parsing

    func testParsesGETRequestWithRange() throws {
        let raw = "GET /0 HTTP/1.1\r\nHost: 192.168.1.10:5000\r\nRange: bytes=0-1048575\r\n\r\n"
        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/0")
        XCTAssertEqual(request.range?.start, 0)
        XCTAssertEqual(request.range?.end, 1_048_575)
    }

    func testParsesGETRequestWithoutRange() throws {
        let raw = "GET /1 HTTP/1.1\r\nHost: 192.168.1.10:5000\r\n\r\n"
        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/1")
        XCTAssertNil(request.range)
    }

    func testParsesHEADRequest() throws {
        let raw = "HEAD /0 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try HTTPRequest.parse(raw)

        XCTAssertEqual(request.method, "HEAD")
        XCTAssertEqual(request.path, "/0")
    }

    // MARK: - Response building

    func testBuilds206PartialContentResponse() {
        let response = HTTPResponse.partialContent(
            data: Data(repeating: 0xAB, count: 100),
            rangeStart: 0,
            rangeEnd: 99,
            totalSize: 1000
        )

        XCTAssertTrue(response.statusLine.contains("206"))
        XCTAssertEqual(response.body.count, 100)
        XCTAssertTrue(response.headers.contains(where: { $0.contains("Content-Range: bytes 0-99/1000") }))
        XCTAssertTrue(response.headers.contains(where: { $0.contains("Content-Length: 100") }))
    }

    func testBuilds200OKResponse() {
        let response = HTTPResponse.ok(
            data: Data(repeating: 0xCC, count: 500),
            totalSize: 500
        )

        XCTAssertTrue(response.statusLine.contains("200"))
        XCTAssertEqual(response.body.count, 500)
    }

    func testBuilds404NotFoundResponse() {
        let response = HTTPResponse.notFound()

        XCTAssertTrue(response.statusLine.contains("404"))
        XCTAssertTrue(response.body.isEmpty)
    }

    // MARK: - File path mapping

    func testFileIndexFromPath() {
        XCTAssertEqual(HTTPRequest.fileIndex(from: "/0"), 0)
        XCTAssertEqual(HTTPRequest.fileIndex(from: "/1"), 1)
        XCTAssertEqual(HTTPRequest.fileIndex(from: "/42"), 42)
        XCTAssertNil(HTTPRequest.fileIndex(from: "/"))
        XCTAssertNil(HTTPRequest.fileIndex(from: "/abc"))
    }
}
