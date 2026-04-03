import XCTest
@testable import DBIProtocol

final class DBIHeaderTests: XCTestCase {
    func testConstantsExist() {
        XCTAssertEqual(DBIConstants.headerSize, 16)
        XCTAssertEqual(DBIConstants.chunkSize, 0x100000)
    }
}
