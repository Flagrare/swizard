import XCTest
@testable import SWizard
@testable import NativeMTPTransport

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
        // Inject mock adapter so test never prompts for password
        state.mtpSessionFactory = { MockMTPSessionForAppState() }

        let logCountBefore = state.coordinator.logs.count

        state.testMTPConnection()
        try? await Task.sleep(for: .seconds(1.0))

        let newLogs = state.coordinator.logs.dropFirst(logCountBefore)
        XCTAssertFalse(newLogs.isEmpty, "MTP diagnostic should write to activity log")
        XCTAssertTrue(newLogs.contains(where: { $0.message.contains("[MTP]") }),
                       "Diagnostic logs should be prefixed with [MTP]")
    }

    func testMTPTestResultStartsAsTesting() async {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.mtpSessionFactory = { MockMTPSessionForAppState() }

        XCTAssertNil(state.mtpTestResult)
        state.testMTPConnection()
        XCTAssertEqual(state.mtpTestResult, "Testing...")
    }
    // MARK: - Device monitoring adapts to transport mode

    func testNetworkModeDoesNotRequireDeviceConnection() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network

        // Network mode should not show "Waiting for Switch"
        // isDeviceConnected is irrelevant for network mode
        // (Install button should work without device in network mode)
        XCTAssertFalse(state.isDeviceConnected)
    }

    func testDefaultMTPModeStartsDisconnected() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        // MTP is default mode — starts disconnected until monitoring detects device
        XCTAssertEqual(state.coordinator.transportMode, .mtp)
        XCTAssertFalse(state.isDeviceConnected)
    }

    // MARK: - Copy logs

    func testCopyLogsReturnsFormattedString() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        state.coordinator.log("First message", level: .info)
        state.coordinator.log("Second error", level: .error)

        let copied = state.copyLogsToString()

        XCTAssertTrue(copied.contains("First message"))
        XCTAssertTrue(copied.contains("Second error"))
        XCTAssertTrue(copied.contains("[INFO]"))
        XCTAssertTrue(copied.contains("[ERROR]"))
    }

    func testCopyLogsIsEmptyWhenNoLogs() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        let copied = state.copyLogsToString()
        XCTAssertTrue(copied.isEmpty)
    }
}

/// Mock MTP session for tests — never prompts for password, fails immediately.
private final class MockMTPSessionForAppState: MTPSessionProtocol, @unchecked Sendable {
    func install(
        files: [PrivilegedMTPSession.FileToInstall],
        onProgress: @escaping @Sendable (String, UInt64, UInt64) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws {
        onLog("Mock session — no real USB")
        throw IOUSBHostError.deviceNotFound
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
