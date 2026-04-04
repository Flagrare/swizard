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
        state.mtpAdapterFactory = { MockBulkTransfer() }

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
        state.mtpAdapterFactory = { MockBulkTransfer() }

        XCTAssertNil(state.mtpTestResult)
        state.testMTPConnection()
        XCTAssertEqual(state.mtpTestResult, "Testing...")
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

/// Mock USB adapter for tests — never prompts for password.
private final class MockBulkTransfer: USBBulkTransferProtocol, @unchecked Sendable {
    func open(vendorID: UInt16, productID: UInt16) async throws {
        throw IOUSBHostError.deviceNotFound
    }
    func close() async {}
    func readBulk(maxLength: Int) async throws -> Data { Data() }
    func writeBulk(_ data: Data) async throws {}
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
