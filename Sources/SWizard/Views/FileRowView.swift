import SwiftUI
import Installer

struct FileRowView: View {
    let file: TransferProgress.FileProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "gamecontroller.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                Text(file.name)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if file.fraction > 0 && !file.isComplete {
                ProgressView(value: file.fraction)
                    .tint(.accentColor)
            }
        }
        .padding(.vertical, 2)
    }

    private var statusText: String {
        if file.isComplete {
            return "Done"
        } else if file.transferredBytes > 0 {
            return "\(Int(file.fraction * 100))%"
        } else {
            return formatBytes(file.totalBytes)
        }
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
