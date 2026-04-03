import SwiftUI
import Installer

struct ContentView: View {
    @Bindable var appState: AppState

    var body: some View {
        HSplitView {
            leftPanel
                .frame(minWidth: 300)

            rightPanel
                .frame(minWidth: 200)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            appState.startMonitoring()
        }
        .onChange(of: appState.coordinator.state) {
            appState.updateTransferFlag()
        }
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            transportModePicker

            Divider()

            ConnectionStatusView(
                isConnected: appState.isDeviceConnected,
                mode: appState.coordinator.transportMode
            )

            if appState.showInstallHelp {
                installHelpBanner
            }

            if let networkInfo = appState.coordinator.networkInfo {
                networkInfoBanner(address: networkInfo)
            }

            Divider()

            DropZoneView { urls in
                appState.coordinator.queueFiles(urls)
            }
            .frame(height: 120)
            .padding()

            Divider()

            FileListView(files: appState.coordinator.progress.files)

            Divider()

            bottomBar
                .padding()
        }
    }

    // MARK: - Transport Mode Picker

    private var transportModePicker: some View {
        Picker("Mode", selection: Binding(
            get: { appState.coordinator.transportMode },
            set: { appState.coordinator.transportMode = $0 }
        )) {
            ForEach(InstallationCoordinator.TransportMode.allCases, id: \.self) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .disabled(appState.isTransferActive)
    }

    // MARK: - Help Banner

    private var installHelpBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.blue)

            VStack(alignment: .leading, spacing: 4) {
                Text("Quick setup tip")
                    .font(.subheadline.weight(.semibold))
                Text(appState.installHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Dismiss") {
                appState.dismissInstallHelp()
            }
            .buttonStyle(.borderless)
            .font(.caption)
        }
        .padding(10)
    }

    private func networkInfoBanner(address: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text("Server running")
                    .font(.subheadline.weight(.semibold))
                Text("http://\(address)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
    }

    // MARK: - Right Panel

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Activity Log")
                .font(.headline)
                .padding(.horizontal)
                .padding(.vertical, 8)

            Divider()

            LogView(entries: appState.coordinator.logs)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            installButton

            Spacer()

            if !appState.coordinator.progress.files.isEmpty {
                Button("Clear Queue") {
                    appState.coordinator.reset()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var installButton: some View {
        switch appState.coordinator.state {
        case .idle:
            Button("Install") {
                appState.coordinator.startInstallation()
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.coordinator.progress.files.isEmpty)

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
            let stats = appState.coordinator.progress.overallStats
            HStack(spacing: 8) {
                ProgressView(value: appState.coordinator.progress.overallFraction)
                    .frame(width: 80)
                Text("\(Int(appState.coordinator.progress.overallFraction * 100))%")
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

                Button("Cancel") {
                    appState.coordinator.cancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
            }

        case .reconnecting(let attempt):
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reconnecting (\(attempt))...")
                    .foregroundStyle(.orange)

                Button("Cancel") {
                    appState.coordinator.cancel()
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
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
}
