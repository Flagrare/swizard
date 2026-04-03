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
    }

    // MARK: - Left Panel

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            ConnectionStatusView(isConnected: appState.isDeviceConnected)

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
            .disabled(!appState.isDeviceConnected || appState.coordinator.progress.files.isEmpty)

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
            HStack(spacing: 8) {
                ProgressView(value: appState.coordinator.progress.overallFraction)
                    .frame(width: 100)
                Text("\(Int(appState.coordinator.progress.overallFraction * 100))%")
                    .font(.system(.body, design: .monospaced))

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
