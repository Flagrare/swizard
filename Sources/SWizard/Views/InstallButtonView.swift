import SwiftUI
import Installer

/// Displays the appropriate install/progress/cancel/complete/error UI based on coordinator state.
struct InstallButtonView: View {
    let state: InstallationCoordinator.State
    let progress: TransferProgress
    let isDisabled: Bool
    let onInstall: () -> Void
    let onCancel: () -> Void

    var body: some View {
        switch state {
        case .idle:
            Button("Install", action: onInstall)
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)

        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting...")
            }

        case .connected:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connected, waiting...")
            }

        case .transferring:
            transferringView

        case .reconnecting(let attempt):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reconnecting (\(attempt))...")
                    .foregroundStyle(.orange)
                cancelButton
            }

        case .complete:
            Label("Complete!", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .error(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)
                .lineLimit(1)
        }
    }

    private var transferringView: some View {
        let stats = progress.overallStats
        return HStack(spacing: 8) {
            ProgressView(value: progress.overallFraction)
                .frame(width: 80)
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

            cancelButton
        }
    }

    private var cancelButton: some View {
        Button("Cancel", action: onCancel)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
    }
}
