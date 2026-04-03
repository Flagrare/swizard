import XCTest
@testable import NetworkTransport

final class HTTPRequestTests: XCTestCase {

    // MARK: - Basic parsing

    func testParsesGETRequest() throws {
        let raw = "GET /0 HTTP/1.1\r\nHost: localhost\r\n\r\n"
        let request = try HTTPRequest.parse(raw)
        XCTAssertEqual(request.method, "GET")
        XCTAssertEqual(request.path, "/0")
        XCTAssertNil(request.range)
    }

    func testParsesHEADRequest() throws {
        let raw = "HEAD /3 HTTP/1.1\r\n\r\n"
        let request = try HTTPRequest.parse(raw)
        XCTAssertEqual(request.method, "HEAD")
        XCTAssertEqual(request.path, "/3")
    }

    func testParsesRequestWithRangeHeader() throws {
        let raw = "GET /1 HTTP/1.1\r\nRange: bytes=100-999\r\n\r\n"
        let request = try HTTPRequest.parse(raw)
        XCTAssertEqual(request.range?.start, 100)
        XCTAssertEqual(request.range?.end, 999)
    }

    func testParsesOpenEndedRange() throws {
        let raw = "GET /0 HTTP/1.1\r\nRange: bytes=500-\r\n\r\n"
        let request = try HTTPRequest.parse(raw)
        XCTAssertEqual(request.range?.start, 500)
        XCTAssertNil(request.range?.end)
    }

    // MARK: - Error cases

    func testEmptyRequestThrows() {
        XCTAssertThrowsError(try HTTPRequest.parse(""))
    }

    func testMalformedRequestLineThrows() {
        XCTAssertThrowsError(try HTTPRequest.parse("GARBAGE\r\n\r\n"))
    }

    // MARK: - Range header edge cases

    func testRangeCaseInsensitive() throws {
        let raw = "GET /0 HTTP/1.1\r\nrange: bytes=0-99\r\n\r\n"
        let request = try HTTPRequest.parse(raw)
        XCTAssertNotNil(request.range)
        XCTAssertEqual(request.range?.start, 0)
    }

    func testMalformedRangeIgnored() throws {
        let raw = "GET /0 HTTP/1.1\r\nRange: invalid\r\n\r\n"
        let request = try HTTPRequest.parse(raw)
        // Malformed range should be nil (graceful degradation)
        XCTAssertNil(request.range)
    }

    // MARK: - File index extraction

    func testFileIndexFromValidPaths() {
        XCTAssertEqual(HTTPRequest.fileIndex(from: "/0"), 0)
        XCTAssertEqual(HTTPRequest.fileIndex(from: "/1"), 1)
        XCTAssertEqual(HTTPRequest.fileIndex(from: "/99"), 99)
    }

    func testFileIndexFromInvalidPaths() {
        XCTAssertNil(HTTPRequest.fileIndex(from: "/"))
        XCTAssertNil(HTTPRequest.fileIndex(from: "/abc"))
        XCTAssertNil(HTTPRequest.fileIndex(from: ""))
        XCTAssertNil(HTTPRequest.fileIndex(from: "/file.nsp"))
    }
}

final class HTTPRangeTests: XCTestCase {

    func testParsesClosedRange() throws {
        let range = try HTTPRange.parse("bytes=0-1048575")
        XCTAssertEqual(range.start, 0)
        XCTAssertEqual(range.end, 1_048_575)
    }

    func testParsesOpenEndedRange() throws {
        let range = try HTTPRange.parse("bytes=100-")
        XCTAssertEqual(range.start, 100)
        XCTAssertNil(range.end)
    }

    func testRejectsNoBytesPrefix() {
        XCTAssertThrowsError(try HTTPRange.parse("0-100"))
    }

    func testRejectsNonNumericStart() {
        XCTAssertThrowsError(try HTTPRange.parse("bytes=abc-100"))
    }

    func testRejectsNonNumericEnd() {
        XCTAssertThrowsError(try HTTPRange.parse("bytes=0-xyz"))
    }

    func testRejectsEmptyValue() {
        XCTAssertThrowsError(try HTTPRange.parse(""))
    }

    func testParsesLargeValues() throws {
        let range = try HTTPRange.parse("bytes=0-17179869183")
        XCTAssertEqual(range.end, 17_179_869_183) // 16GB
    }
}
