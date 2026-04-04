import XCTest
@testable import NetworkTransport

final class CurlProgressParserTests: XCTestCase {

    // curl with --progress-bar outputs lines like:
    // ###                                               7.2%
    // ########################################          100.0%

    func testParsesPercentageFromProgressLine() {
        let result = CurlProgressParser.parse("###                                               7.2%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.percentage, 7.2, accuracy: 0.1)
    }

    func testParses100Percent() {
        let result = CurlProgressParser.parse("########################################          100.0%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.percentage, 100.0, accuracy: 0.1)
    }

    func testParsesZeroPercent() {
        let result = CurlProgressParser.parse("                                                  0.0%")
        XCTAssertNotNil(result)
        XCTAssertEqual(result!.percentage, 0.0, accuracy: 0.1)
    }

    func testReturnsNilForNonProgressLine() {
        XCTAssertNil(CurlProgressParser.parse("  % Total    % Received % Xferd"))
        XCTAssertNil(CurlProgressParser.parse("* Connected to 192.168.0.96"))
        XCTAssertNil(CurlProgressParser.parse(""))
    }

    func testCalculatesBytesFromPercentage() {
        let result = CurlProgressParser.parse("###                                               50.0%")
        let bytes = result?.bytesUploaded(totalSize: 1000)
        XCTAssertEqual(bytes, 500)
    }
}
