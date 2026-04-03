import SwiftUI

@main
struct SWizardApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 480)
    }
}
