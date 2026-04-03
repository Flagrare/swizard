import XCTest
@testable import SWizard

@MainActor
final class AppStateTests: XCTestCase {

    func testShowInstallHelpDefaultsToTrueWhenNotDismissed() {
        let store = InMemoryPreferencesStore()

        let state = AppState(preferences: store)

        XCTAssertTrue(state.showInstallHelp)
    }

    func testShowInstallHelpIsFalseWhenPreviouslyDismissed() {
        let store = InMemoryPreferencesStore()
        store.set(true, forKey: "swizard.installHelp.dismissed")

        let state = AppState(preferences: store)

        XCTAssertFalse(state.showInstallHelp)
    }

    func testDismissInstallHelpPersistsAcrossNewAppState() {
        let store = InMemoryPreferencesStore()
        let firstState = AppState(preferences: store)

        firstState.dismissInstallHelp()
        let secondState = AppState(preferences: store)

        XCTAssertFalse(firstState.showInstallHelp)
        XCTAssertFalse(secondState.showInstallHelp)
    }
}

private final class InMemoryPreferencesStore: PreferencesStore {
    private var values: [String: Bool] = [:]

    func bool(forKey defaultName: String) -> Bool {
        values[defaultName] ?? false
    }

    func set(_ value: Bool, forKey defaultName: String) {
        values[defaultName] = value
    }
}
