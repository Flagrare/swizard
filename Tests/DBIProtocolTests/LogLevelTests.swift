import XCTest
@testable import DBIProtocol

final class LogLevelTests: XCTestCase {

    func testLevelOrdering() {
        XCTAssertTrue(LogLevel.debug < LogLevel.info)
        XCTAssertTrue(LogLevel.info < LogLevel.warning)
        XCTAssertTrue(LogLevel.warning < LogLevel.error)
    }

    func testDebugIsLowestLevel() {
        XCTAssertEqual(LogLevel.allCases.first, .debug)
    }

    func testErrorIsHighestLevel() {
        XCTAssertEqual(LogLevel.allCases.last, .error)
    }

    func testAllCasesCount() {
        XCTAssertEqual(LogLevel.allCases.count, 4)
    }

    func testFilteringByMinimumLevel() {
        let allLogs: [(String, LogLevel)] = [
            ("debug msg", .debug),
            ("info msg", .info),
            ("warning msg", .warning),
            ("error msg", .error),
        ]

        let warningAndAbove = allLogs.filter { $0.1 >= .warning }
        XCTAssertEqual(warningAndAbove.count, 2)
        XCTAssertEqual(warningAndAbove[0].0, "warning msg")
        XCTAssertEqual(warningAndAbove[1].0, "error msg")
    }
}
