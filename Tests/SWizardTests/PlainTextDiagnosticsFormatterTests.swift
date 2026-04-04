import XCTest
import DBIProtocol
import Installer
@testable import SWizard

final class PlainTextDiagnosticsFormatterTests: XCTestCase {

    func testReportIncludesMetadataAndLogs() {
        let formatter = PlainTextDiagnosticsFormatter(timestampFormatter: { _ in "TIME" })
        let context = DiagnosticsContext(
            generatedAt: Date(timeIntervalSince1970: 1000),
            appVersion: "1.2.3",
            transportMode: "MTP",
            installationState: "idle"
        )
        let entries = [
            LogEntry(message: "Started", level: .info),
            LogEntry(message: "Oops", level: .error)
        ]

        let report = formatter.makeReport(context: context, entries: entries)

        XCTAssertTrue(report.contains("SWizard Diagnostics Report"))
        XCTAssertTrue(report.contains("Generated: TIME"))
        XCTAssertTrue(report.contains("App Version: 1.2.3"))
        XCTAssertTrue(report.contains("Transport Mode: MTP"))
        XCTAssertTrue(report.contains("Installation State: idle"))
        XCTAssertTrue(report.contains("[TIME] [INFO] Started"))
        XCTAssertTrue(report.contains("[TIME] [ERROR] Oops"))
    }

    func testReportMarksEmptyLogList() {
        let formatter = PlainTextDiagnosticsFormatter(timestampFormatter: { _ in "TIME" })
        let context = DiagnosticsContext(
            generatedAt: Date(),
            appVersion: "dev",
            transportMode: "Network",
            installationState: "connecting"
        )

        let report = formatter.makeReport(context: context, entries: [])

        XCTAssertTrue(report.contains("Logs:"))
        XCTAssertTrue(report.contains("(no log entries)"))
    }

    func testReportEscapesMultilineMessages() {
        let formatter = PlainTextDiagnosticsFormatter(timestampFormatter: { _ in "TIME" })
        let context = DiagnosticsContext(
            generatedAt: Date(),
            appVersion: "dev",
            transportMode: "Network",
            installationState: "error(bad)"
        )
        let entries = [LogEntry(message: "line1\nline2", level: .warning)]

        let report = formatter.makeReport(context: context, entries: entries)

        XCTAssertTrue(report.contains("[TIME] [WARNING] line1\\nline2"))
    }
}
