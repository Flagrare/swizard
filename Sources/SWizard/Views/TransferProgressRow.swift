import SwiftUI
import Installer

/// Full-width progress readout shown above the install controls while bytes are moving.
struct TransferProgressRow: View {
    let progress: TransferProgress

    var body: some View {
        let stats = progress.overallStats
        HStack(spacing: 8) {
            ProgressView(value: progress.overallFraction)

            Text("\(Int(progress.overallFraction * 100))%")
                .font(.system(.caption, design: .monospaced))

            if stats.bytesPerSecond > 0 {
                Text(stats.formattedSpeed)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if let eta = stats.formattedETA {
                Text(eta)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
