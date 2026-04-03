import SwiftUI
import Installer
import DBIProtocol

struct LogView: View {
    let entries: [LogEntry]
    @State private var minimumLevel: LogLevel = .debug

    private var filteredEntries: [LogEntry] {
        entries.filter { $0.level >= minimumLevel }
    }

    var body: some View {
        VStack(spacing: 0) {
            levelFilterBar
            Divider()
            logContent
        }
    }

    // MARK: - Filter Bar

    private var levelFilterBar: some View {
        Picker("Level", selection: $minimumLevel) {
            Text("All").tag(LogLevel.debug)
            Text("Info").tag(LogLevel.info)
            Text("Warn").tag(LogLevel.warning)
            Text("Error").tag(LogLevel.error)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        logRow(entry)
                            .id(entry.id)
                    }
                }
                .padding(8)
            }
            .onChange(of: entries.count) {
                if let last = filteredEntries.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func logRow(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(entry.timestamp, format: .dateTime.hour().minute().second())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(colorForLevel(entry.level))
                .textSelection(.enabled)
        }
    }

    private func colorForLevel(_ level: LogLevel) -> Color {
        switch level {
        case .debug: .secondary
        case .info: .primary
        case .warning: .orange
        case .error: .red
        }
    }
}
