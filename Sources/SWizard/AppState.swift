import Foundation
import Installer
import USBTransport

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

    func dismissInstallHelp() {
        showInstallHelp = false
        preferences.set(true, forKey: Self.installHelpDismissedKey)
    }
}

/// Thread-safe flag bridging @MainActor state to background polling.
final class TransferActiveFlag: @unchecked Sendable {
    var value: Bool = false
}
