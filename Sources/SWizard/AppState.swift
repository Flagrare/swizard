import Foundation
import Installer
import USBTransport

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

    /// Shared flag for device mutex — set by coordinator state changes.
    private let _isTransferActive = TransferActiveFlag()

    init() {
        let flag = _isTransferActive
        self.deviceMonitor = USBDeviceMonitor { flag.value }
        self.showInstallHelp = !UserDefaults.standard.bool(forKey: Self.installHelpDismissedKey)
    }

    var isTransferActive: Bool {
        switch coordinator.state {
        case .transferring, .reconnecting: return true
        default: return false
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

    /// Call this whenever coordinator state changes to keep the mutex flag in sync.
    func updateTransferFlag() {
        _isTransferActive.value = isTransferActive
    }

    func dismissInstallHelp() {
        showInstallHelp = false
        UserDefaults.standard.set(true, forKey: Self.installHelpDismissedKey)
    }
}

/// Thread-safe flag bridging @MainActor state to background polling.
final class TransferActiveFlag: @unchecked Sendable {
    var value: Bool = false
}
