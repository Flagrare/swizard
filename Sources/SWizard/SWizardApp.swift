import SwiftUI
import AppKit

@main
struct SWizardApp: App {
    @State private var appState = AppState()

    init() {
        // SPM executables launch as background processes by default.
        // This makes the app a proper foreground GUI app with Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
    }
}
