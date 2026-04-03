import SwiftUI
import Installer

struct ContentView: View {
    @Bindable var appState: AppState

    /// USB modes require a connected device; Network mode doesn't.
    private var installRequiresDevice: Bool {
        switch appState.coordinator.transportMode {
        case .dbiBackend, .mtp:
            return !appState.isDeviceConnected
        case .network:
            return false
        }
    }

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

    private var installButton: some View {
        InstallButtonView(
            state: appState.coordinator.state,
            progress: appState.coordinator.progress,
            isDisabled: appState.coordinator.progress.files.isEmpty || installRequiresDevice,
            onInstall: { appState.coordinator.startInstallation() },
            onCancel: { appState.coordinator.cancel() }
        )
    }
}
