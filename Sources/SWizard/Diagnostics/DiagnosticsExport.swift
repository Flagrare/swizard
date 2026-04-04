import Foundation
import AppKit
import Installer
import DBIProtocol

struct DiagnosticsContext {
    let generatedAt: Date
    let appVersion: String
    let transportMode: String
    let installationState: String
}

struct DiagnosticsExportRequest {
    let appVersion: String
    let transportMode: String
    let installationState: String
}

protocol DiagnosticsReportFormatting {
    func makeReport(context: DiagnosticsContext, entries: [LogEntry]) -> String
}

protocol DiagnosticsExporting {
    @MainActor
    func export(report: String, suggestedFileName: String) throws -> URL?
}

protocol DiagnosticsExportRunning {
    @MainActor
    func export(request: DiagnosticsExportRequest, entries: [LogEntry]) throws -> URL?
}

struct PlainTextDiagnosticsFormatter: DiagnosticsReportFormatting {
    private let timestampFormatter: (Date) -> String

    init(timestampFormatter: @escaping (Date) -> String = PlainTextDiagnosticsFormatter.defaultTimestampString) {
        self.timestampFormatter = timestampFormatter
    }

    func makeReport(context: DiagnosticsContext, entries: [LogEntry]) -> String {
        var lines: [String] = []
        lines.append("SWizard Diagnostics Report")
        lines.append("Generated: \(timestampFormatter(context.generatedAt))")
        lines.append("App Version: \(context.appVersion)")
        lines.append("Transport Mode: \(context.transportMode)")
        lines.append("Installation State: \(context.installationState)")
        lines.append("")
        lines.append("Logs:")

        if entries.isEmpty {
            lines.append("(no log entries)")
        } else {
            for entry in entries {
                let message = entry.message.replacingOccurrences(of: "\n", with: "\\n")
                lines.append("[\(timestampFormatter(entry.timestamp))] [\(label(for: entry.level))] \(message)")
            }
        }

        return lines.joined(separator: "\n")
    }

    private func label(for level: LogLevel) -> String {
        switch level {
        case .debug: "DEBUG"
        case .info: "INFO"
        case .warning: "WARNING"
        case .error: "ERROR"
        }
    }

    private static func defaultTimestampString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

struct SavePanelDiagnosticsExporter: DiagnosticsExporting {
    @MainActor
    func export(report: String, suggestedFileName: String) throws -> URL? {
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.nameFieldStringValue = suggestedFileName
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        try report.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

struct DiagnosticsExportUseCase: DiagnosticsExportRunning {
    private let formatter: any DiagnosticsReportFormatting
    private let exporter: any DiagnosticsExporting
    private let now: () -> Date
    private let fileNameTimestampFormatter: (Date) -> String

    init(
        formatter: any DiagnosticsReportFormatting,
        exporter: any DiagnosticsExporting,
        now: @escaping () -> Date = Date.init,
        fileNameTimestampFormatter: @escaping (Date) -> String = DiagnosticsExportUseCase.defaultFileNameTimestamp
    ) {
        self.formatter = formatter
        self.exporter = exporter
        self.now = now
        self.fileNameTimestampFormatter = fileNameTimestampFormatter
    }

    @MainActor
    func export(request: DiagnosticsExportRequest, entries: [LogEntry]) throws -> URL? {
        let generatedAt = now()
        let context = DiagnosticsContext(
            generatedAt: generatedAt,
            appVersion: request.appVersion,
            transportMode: request.transportMode,
            installationState: request.installationState
        )
        let report = formatter.makeReport(context: context, entries: entries)
        let fileName = "SWizard-diagnostics-\(fileNameTimestampFormatter(generatedAt)).log"
        return try exporter.export(report: report, suggestedFileName: fileName)
    }

    static func defaultFileNameTimestamp(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
