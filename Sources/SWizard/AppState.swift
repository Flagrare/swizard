import Foundation
import Installer
import USBTransport

/// Top-level observable state for the app.
@Observable
@MainActor
final class AppState {
    let coordinator = InstallationCoordinator()
    let deviceMonitor = USBDeviceMonitor()
    var isDeviceConnected = false
    private var monitorTask: Task<Void, Never>?

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
}
