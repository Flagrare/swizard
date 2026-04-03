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
    // MARK: - MTP Diagnostic logs to activity log

    func testMTPDiagnosticLogsToActivityLog() async {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        // Before running diagnostic, activity log should be empty or have only startup logs
        let logCountBefore = state.coordinator.logs.count

        // Run diagnostic (will fail since no Switch is connected — that's fine)
        state.testMTPConnection()
        try? await Task.sleep(for: .seconds(0.5))

        // Activity log should have new entries from the diagnostic
        let newLogs = state.coordinator.logs.dropFirst(logCountBefore)
        XCTAssertFalse(newLogs.isEmpty, "MTP diagnostic should write to activity log")
        XCTAssertTrue(newLogs.contains(where: { $0.message.contains("[MTP]") }),
                       "Diagnostic logs should be prefixed with [MTP]")
    }

    func testMTPTestResultStartsAsTesting() async {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        XCTAssertNil(state.mtpTestResult)
        state.testMTPConnection()
        // Immediately after calling, should be "Testing..."
        XCTAssertEqual(state.mtpTestResult, "Testing...")
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
