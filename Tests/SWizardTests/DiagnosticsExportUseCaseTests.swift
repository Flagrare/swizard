import XCTest
import Installer
@testable import SWizard

@MainActor
final class DiagnosticsExportUseCaseTests: XCTestCase {

    func testExportPassesAllEntriesAndBuildsExpectedFileName() throws {
        let formatter = SpyFormatter()
        let exporter = SpyExporter()
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        let useCase = DiagnosticsExportUseCase(
            formatter: formatter,
            exporter: exporter,
            now: { fixedDate },
            fileNameTimestampFormatter: { _ in "2023-11-14-221320" }
        )
        let request = DiagnosticsExportRequest(
            appVersion: "1.0.0",
            transportMode: "MTP",
            installationState: "idle"
        )
        let entries = [
            LogEntry(message: "a", level: .info),
            LogEntry(message: "b", level: .error)
        ]

        _ = try useCase.export(request: request, entries: entries)

        XCTAssertEqual(formatter.receivedEntries.count, 2)
        XCTAssertEqual(formatter.receivedContext?.appVersion, "1.0.0")
        XCTAssertEqual(formatter.receivedContext?.transportMode, "MTP")
        XCTAssertEqual(formatter.receivedContext?.installationState, "idle")
        XCTAssertEqual(formatter.receivedContext?.generatedAt, fixedDate)
        XCTAssertEqual(exporter.receivedSuggestedFileName, "SWizard-diagnostics-2023-11-14-221320.log")
    }

    func testDefaultFileNameTimestampFormat() {
        let date = Date(timeIntervalSince1970: 0)

        let value = DiagnosticsExportUseCase.defaultFileNameTimestamp(from: date)

        XCTAssertFalse(value.isEmpty)
        XCTAssertTrue(value.contains("-"))
    }
}

private final class SpyFormatter: DiagnosticsReportFormatting {
    private(set) var receivedContext: DiagnosticsContext?
    private(set) var receivedEntries: [Installer.LogEntry] = []

    func makeReport(context: DiagnosticsContext, entries: [Installer.LogEntry]) -> String {
        receivedContext = context
        receivedEntries = entries
        return "report"
    }
}

private final class SpyExporter: DiagnosticsExporting {
    private(set) var receivedSuggestedFileName: String?

    @MainActor
    func export(report: String, suggestedFileName: String) throws -> URL? {
        receivedSuggestedFileName = suggestedFileName
        return nil
    }
}
