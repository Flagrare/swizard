import SwiftUI
import Installer
import NativeMTPTransport

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

            if appState.coordinator.transportMode == .mtp {
                mtpAdminWarning
            }

            Divider()

            ConnectionStatusView(
                isConnected: appState.isDeviceConnected,
                mode: appState.coordinator.transportMode
            )

            if appState.coordinator.transportMode == .mtp {
                mtpTestSection
                mtpDestinationPicker
            }

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

    // MARK: - MTP Test

    private var mtpTestSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button("Test MTP Connection") {
                    appState.testMTPConnection()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if let result = appState.mtpTestResult {
                    Text(result)
                        .font(.caption2)
                        .foregroundStyle(result.contains("SUCCESS") ? .green : result.contains("Testing") ? .secondary : .red)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    // MARK: - MTP Admin Warning

    private var mtpAdminWarning: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(.orange)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text("Admin Password Required")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.orange)
                Text("macOS requires admin privileges to access USB in MTP mode. You'll be prompted for your password when installing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .padding(.horizontal)
    }

    // MARK: - MTP Destination Picker

    private var mtpDestinationPicker: some View {
        HStack {
            Text("Install to:")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { appState.coordinator.mtpInstallDestination ?? MTPInstallDestination(storageID: 0, rawName: "SD Card install") },
                set: { appState.coordinator.mtpInstallDestination = $0 }
            )) {
                Text("SD Card").tag(MTPInstallDestination(storageID: 0, rawName: "SD Card install"))
                Text("NAND").tag(MTPInstallDestination(storageID: 0, rawName: "NAND install"))
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
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
                    .fixedSize(horizontal: false, vertical: true)
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
            HStack {
                Text("Activity Log")
                    .font(.headline)

                Spacer()

                Button {
                    appState.exportDiagnosticsLogs()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Export diagnostics log file")

                Button {
                    appState.copyLogsToClipboard()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Copy logs to clipboard")
                .disabled(appState.coordinator.logs.isEmpty)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            if let exportStatus = appState.diagnosticsExportStatusMessage {
                Text(exportStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                    .padding(.bottom, 6)
            }

            Divider()

            LogView(entries: appState.coordinator.logs)
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack {
            installButton

            Spacer()

            Text(appState.appVersionDisplay)
                .font(.caption2)
                .foregroundStyle(.secondary)

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
