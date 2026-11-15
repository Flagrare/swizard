import SwiftUI
import Installer

/// The primary install control for the current coordinator state (Install / Cancel / Retry).
struct InstallButtonView: View {
    let state: InstallationCoordinator.State
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
            busy("Connecting...")

        case .connected:
            busy("Connected, waiting...")

        case .waitingForSwitch:
            HStack(spacing: 8) {
                busy("Choose the game on your Switch")
                cancelButton
            }

        case .transferring:
            HStack(spacing: 8) {
                Text("Installing...")
                    .foregroundStyle(.secondary)
                cancelButton
            }

        case .reconnecting(let attempt):
            HStack(spacing: 8) {
                busy("Reconnecting (\(attempt))...")
                    .foregroundStyle(.orange)
                cancelButton
            }

        case .complete:
            Label("Complete!", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)

        case .error:
            Button("Retry", action: onInstall)
                .buttonStyle(.borderedProminent)
                .disabled(isDisabled)
        }
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(text)
                .lineLimit(2)
        }
    }

    private var cancelButton: some View {
        Button("Cancel", action: onCancel)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .fixedSize()
    }
}
