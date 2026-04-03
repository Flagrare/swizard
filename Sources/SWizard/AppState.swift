import Foundation
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
            "On your Switch, open DBI and select \"Run MTP responder\" before connecting USB."
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
        logMTP("Starting MTP connection diagnostic...", level: .info)

        // Step 1: Scan for device
        let devices = USBDeviceScanner.findDevices(vendorID: NintendoSwitchUSB.vendorID)
        if devices.isEmpty {
            logMTP("No Nintendo USB device found", level: .error)
            mtpTestResult = "FAILED — No Nintendo device found"
            return
        }
        for d in devices {
            logMTP("Found: \(d.description)", level: .info)
        }

        // Step 2: Try adapter open (includes privileged claim)
        logMTP("Requesting admin privileges for USB claim...", level: .warning)
        let adapter = IOUSBHostAdapter()
        do {
            try await adapter.open(
                vendorID: NintendoSwitchUSB.vendorID,
                productID: NintendoSwitchUSB.mtpProductID
            )
            logMTP("SUCCESS — Device and interface opened!", level: .info)
            mtpTestResult = "SUCCESS — MTP access confirmed!"

            await adapter.close()
            logMTP("Device closed cleanly", level: .debug)
        } catch {
            logMTP("Open failed: \(error.localizedDescription)", level: .error)

            // Extra diagnostic: check what's in IORegistry after the attempt
            logMTP("Post-failure device scan:", level: .debug)
            let postDevices = USBDeviceScanner.findDevices(vendorID: NintendoSwitchUSB.vendorID)
            for d in postDevices {
                logMTP("  Still present: \(d.description)", level: .debug)
            }

            let found = devices.map(\.description).joined(separator: ", ")
            mtpTestResult = "FAILED — \(found). \(error.localizedDescription)"
        }
    }

    func dismissInstallHelp() {
        showInstallHelp = false
        preferences.set(true, forKey: Self.installHelpDismissedKey)
    }

    // MARK: - MTP Connection Test

    var mtpTestResult: String?

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
