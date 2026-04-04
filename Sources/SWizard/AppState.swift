import Foundation
import AppKit
import os
import Installer
import USBTransport
import NativeMTPTransport
import DBIProtocol

protocol PreferencesStore {
    func bool(forKey defaultName: String) -> Bool
    func set(_ value: Bool, forKey defaultName: String)
}

extension UserDefaults: PreferencesStore {}

/// Top-level observable state for the app.
@Observable
@MainActor
final class AppState {
    private static let installHelpDismissedKey = "swizard.installHelp.dismissed"

    let coordinator = InstallationCoordinator()
    let deviceMonitor: USBDeviceMonitor
    var isDeviceConnected = false
    var showInstallHelp: Bool
    var diagnosticsExportStatusMessage: String?
    private var monitorTask: Task<Void, Never>?
    private let preferences: PreferencesStore
    private let appVersionProvider: any AppVersionProviding
    private let diagnosticsExportRunner: any DiagnosticsExportRunning

    /// Shared flag for device mutex — set by coordinator state changes.
    private let _isTransferActive = TransferActiveFlag()

    init(
        preferences: PreferencesStore = UserDefaults.standard,
        appVersionProvider: any AppVersionProviding = DefaultAppVersionProvider(),
        diagnosticsExportRunner: (any DiagnosticsExportRunning)? = nil
    ) {
        let flag = _isTransferActive
        self.preferences = preferences
        self.appVersionProvider = appVersionProvider
        if let diagnosticsExportRunner {
            self.diagnosticsExportRunner = diagnosticsExportRunner
        } else {
            self.diagnosticsExportRunner = DiagnosticsExportUseCase(
                formatter: PlainTextDiagnosticsFormatter(),
                exporter: SavePanelDiagnosticsExporter()
            )
        }
        self.deviceMonitor = USBDeviceMonitor { flag.value }
        self.showInstallHelp = !preferences.bool(forKey: Self.installHelpDismissedKey)
    }

    var isTransferActive: Bool {
        switch coordinator.state {
        case .transferring, .reconnecting: return true
        default: return false
        }
    }

    var appVersionDisplay: String {
        let version = appVersionProvider.displayVersion
        guard shouldPrefixVersion(version) else { return version }
        return "v\(version)"
    }

    private func shouldPrefixVersion(_ version: String) -> Bool {
        guard let first = version.first else { return false }
        return first.isNumber
    }

    /// Help text depends on the selected mode.
    var installHelpText: String {
        switch coordinator.transportMode {
        case .dbiBackend:
            "On your Switch, open DBI and select \"Run DBI backend\" before connecting USB."
        case .mtp:
            "On your Switch, open DBI → \"Run MTP responder\". SWizard will ask for your admin password once to claim USB from macOS."
        case .network:
            "On your Switch: DBI → Start FTP → Install on SD Card. Enter the IP:port shown on the Switch."
        }
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task {
            // Poll for device based on current transport mode
            var wasConnected = false
            while !Task.isCancelled {
                let found: Bool
                switch coordinator.transportMode {
                case .dbiBackend:
                    // Use USBDeviceMonitor's underlying check (libusb, PID 0x3000)
                    found = USBDeviceScanner.findDevice(
                        vendorID: NintendoSwitchUSB.vendorID,
                        productID: NintendoSwitchUSB.backendProductID
                    ) != nil
                case .mtp:
                    // Scan for MTP PID (0x201D)
                    found = USBDeviceScanner.findDevice(
                        vendorID: NintendoSwitchUSB.vendorID,
                        productID: NintendoSwitchUSB.mtpProductID
                    ) != nil
                case .network:
                    // Network mode doesn't need USB detection
                    found = false
                }

                if found != wasConnected {
                    isDeviceConnected = found
                    wasConnected = found
                }

                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
    }

    func updateTransferFlag() {
        _isTransferActive.value = isTransferActive
    }

    private func logMTP(_ msg: String, level: DBIProtocol.LogLevel = .info) {
        coordinator.log("[MTP] \(msg)", level: level)
    }

    private func runMTPDiagnostic() async {
        logMTP("Starting MTP connection test...", level: .info)

        // Step 1: Scan for device (no admin needed)
        let devices = USBDeviceScanner.findDevices(vendorID: NintendoSwitchUSB.vendorID)
        if devices.isEmpty {
            logMTP("No Nintendo USB device found", level: .error)
            mtpTestResult = "FAILED — No Nintendo device found. Is the Switch connected with DBI MTP running?"
            return
        }
        for d in devices {
            logMTP("Found: \(d.description)", level: .info)
        }

        // Step 2: Run a quick MTP handshake test via PrivilegedMTPSession
        // This prompts for admin password, then does DeviceCapture → OpenSession → CloseSession
        logMTP("Testing MTP handshake (will ask for admin password)...", level: .warning)

        let session = mtpSessionFactory()
        do {
            // Install with empty file list — just tests the handshake
            try await session.install(
                files: [],
                targetStorageID: nil,
                onProgress: { _, _, _ in },
                onLog: { [weak self] msg in
                    Task { @MainActor in self?.logMTP(msg, level: .debug) }
                }
            )
            logMTP("SUCCESS — MTP handshake completed!", level: .info)
            mtpTestResult = "SUCCESS — MTP access confirmed!"
        } catch {
            logMTP("MTP handshake failed: \(error.localizedDescription)", level: .error)
            let found = devices.map(\.description).joined(separator: ", ")
            mtpTestResult = "FAILED — \(found). \(error.localizedDescription)"
        }
    }

    func dismissInstallHelp() {
        showInstallHelp = false
        preferences.set(true, forKey: Self.installHelpDismissedKey)
    }

    // MARK: - Copy Logs

    /// Formats all activity log entries as a string and copies to clipboard.
    @discardableResult
    func copyLogsToString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let text = coordinator.logs.map { entry in
            let level = "[\(String(describing: entry.level).uppercased())]"
            let time = formatter.string(from: entry.timestamp)
            return "\(time) \(level) \(entry.message)"
        }.joined(separator: "\n")

        return text
    }

    func copyLogsToClipboard() {
        let text = copyLogsToString()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func exportDiagnosticsLogs() {
        let request = DiagnosticsExportRequest(
            appVersion: appVersionProvider.displayVersion,
            transportMode: coordinator.transportMode.rawValue,
            installationState: coordinator.state.diagnosticsLabel
        )

        do {
            let exportedURL = try diagnosticsExportRunner.export(request: request, entries: coordinator.logs)
            if let exportedURL {
                diagnosticsExportStatusMessage = "Diagnostics exported to \(exportedURL.lastPathComponent)."
            } else {
                diagnosticsExportStatusMessage = "Diagnostics export cancelled."
            }
        } catch {
            diagnosticsExportStatusMessage = "Failed to export diagnostics: \(error.localizedDescription)"
        }
    }

    // MARK: - MTP Connection Test

    var mtpTestResult: String?

    /// Injectable for testing — defaults to real PrivilegedMTPSession.
    var mtpSessionFactory: () -> any MTPSessionProtocol = { PrivilegedMTPSession() }

    func testMTPConnection() {
        mtpTestResult = "Testing..."
        Task {
            await runMTPDiagnostic()
        }
    }
}

private extension InstallationCoordinator.State {
    var diagnosticsLabel: String {
        switch self {
        case .idle: "idle"
        case .connecting: "connecting"
        case .connected: "connected"
        case .transferring: "transferring"
        case .reconnecting(let attempt): "reconnecting(\(attempt))"
        case .complete: "complete"
        case .error(let message): "error(\(message))"
        }
    }
}

/// Thread-safe flag bridging @MainActor state to background polling.
/// Uses os_unfair_lock for safe concurrent read/write.
final class TransferActiveFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var value: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
