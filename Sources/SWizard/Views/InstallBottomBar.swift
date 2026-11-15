import SwiftUI
import Installer

/// Bottom of the left panel: progress (own row), error detail, and the install controls.
struct InstallBottomBar: View {
    @Bindable var appState: AppState

    private var coordinator: InstallationCoordinator { appState.coordinator }

    /// USB modes require a connected device; Network mode doesn't.
    private var installRequiresDevice: Bool {
        switch coordinator.transportMode {
        case .dbiBackend, .mtp:
            return !appState.isDeviceConnected
        case .network:
            return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if coordinator.state == .transferring {
                TransferProgressRow(progress: coordinator.progress)
            }

            if case .error(let message) = coordinator.state {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .help(message)
            }

            HStack {
                InstallButtonView(
                    state: coordinator.state,
                    isDisabled: coordinator.progress.files.isEmpty || installRequiresDevice,
                    onInstall: { coordinator.startInstallation() },
                    onCancel: { coordinator.cancel() }
                )

                Spacer()

                if !coordinator.state.isBusy {
                    Text(appState.appVersionDisplay)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if appState.canClearQueue {
                    Button("Clear Queue") {
                        coordinator.clearQueue()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}
