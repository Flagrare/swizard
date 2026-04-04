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
    private var monitorTask: Task<Void, Never>?
    private let preferences: PreferencesStore

    /// Shared flag for device mutex — set by coordinator state changes.
    private let _isTransferActive = TransferActiveFlag()

    init(preferences: PreferencesStore = UserDefaults.standard) {
        let flag = _isTransferActive
        self.preferences = preferences
        self.deviceMonitor = USBDeviceMonitor { flag.value }
        self.showInstallHelp = !preferences.bool(forKey: Self.installHelpDismissedKey)
    }

    var isTransferActive: Bool {
        switch coordinator.state {
        case .transferring, .reconnecting: return true
        default: return false
        }
    }

    /// Help text depends on the selected mode.
    var installHelpText: String {
        switch coordinator.transportMode {
        case .dbiBackend:
            "On your Switch, open DBI and select \"Run DBI backend\" before connecting USB."
        case .mtp:
            "On your Switch, open DBI → \"Run MTP responder\". SWizard will ask for your admin password once to claim USB from macOS."
        case .network:
            "Drop files, click Install, then on your Switch: DBI → Run HTTP server → enter the URL shown below."
        }
    }

    func startMonitoring() {
        monitorTask?.cancel()
        monitorTask = Task {
            for await event in deviceMonitor.events() {
                switch event {
                case .connected:
                    isDeviceConnected = true
                case .disconnected:
                    isDeviceConnected = false
                }
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

/// Thread-safe flag bridging @MainActor state to background polling.
/// Uses os_unfair_lock for safe concurrent read/write.
final class TransferActiveFlag: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    var value: Bool {
        get { lock.withLock { $0 } }
        set { lock.withLock { $0 = newValue } }
    }
}
