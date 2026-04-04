import XCTest
@testable import SWizard
@testable import NativeMTPTransport
import Installer

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

    func testNetworkModeShowsConnectedWhenFTPAddressEntered() async {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network
        state.coordinator.ftpAddress = "192.168.0.96:5000"
        state.validateFTPAddress() // User must click Connect

        state.startMonitoring()
        try? await Task.sleep(for: .seconds(1.5))

        XCTAssertTrue(state.isDeviceConnected,
                       "Network mode should show connected after validating FTP address")
        state.stopMonitoring()
    }

    func testNetworkModeShowsDisconnectedWhenFTPAddressEmpty() async {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network
        state.coordinator.ftpAddress = ""

        state.startMonitoring()
        try? await Task.sleep(for: .seconds(1.5))

        XCTAssertFalse(state.isDeviceConnected,
                        "Network mode should show disconnected when FTP address is empty")
        state.stopMonitoring()
    }

    // MARK: - FTP address validation

    func testEnterValidAddressAndClickConnect_ShowsReady() async {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network

        // User types address
        state.coordinator.ftpAddress = "192.168.0.96:5000"
        // User clicks Connect
        state.validateFTPAddress()

        // Should show ready (no error, connection status green)
        state.startMonitoring()
        try? await Task.sleep(for: .seconds(1.5))
        XCTAssertNil(state.ftpValidationError)
        XCTAssertTrue(state.isDeviceConnected)
        state.stopMonitoring()
    }

    func testClickConnectWithEmptyAddress_ShowsError() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network

        // User leaves address empty and clicks Connect
        state.coordinator.ftpAddress = ""
        state.validateFTPAddress()

        // Should show error message
        XCTAssertNotNil(state.ftpValidationError)
    }

    func testClickConnectWithInvalidPort_ShowsError() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network

        // User types invalid port
        state.coordinator.ftpAddress = "192.168.0.96:abc"
        state.validateFTPAddress()

        // Should show error message
        XCTAssertNotNil(state.ftpValidationError)
    }

    func testEnterHostOnly_DefaultsPort_ShowsReady() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network

        // User types just the IP without port
        state.coordinator.ftpAddress = "192.168.0.96"
        state.validateFTPAddress()

        // Host only should be valid — uses default port
        XCTAssertNil(state.ftpValidationError)
        XCTAssertTrue(state.ftpAddressValidated)
    }

    func testDefaultMTPModeStartsDisconnected() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        // MTP is default mode — starts disconnected until monitoring detects device
        XCTAssertEqual(state.coordinator.transportMode, .mtp)
        XCTAssertFalse(state.isDeviceConnected)
    }

    // MARK: - FTP address persistence

    func testSuccessfulConnectSavesAddress() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network
        state.coordinator.ftpAddress = "192.168.0.96:5000"

        state.validateFTPAddress()

        // Address should be persisted for next launch
        XCTAssertEqual(store.string(forKey: "swizard.ftp.lastAddress"), "192.168.0.96:5000")
    }

    func testPreviousAddressRestoredOnLaunch() {
        let store = InMemoryPreferencesStore()
        store.setString("10.0.0.5:6000", forKey: "swizard.ftp.lastAddress")

        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network

        // Should pre-fill the FTP address from last session
        XCTAssertEqual(state.coordinator.ftpAddress, "10.0.0.5:6000")
    }

    // MARK: - Transport mode persistence

    func testTransportModeSavedOnChange() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)

        state.setTransportMode(.dbiBackend)
        XCTAssertEqual(store.string(forKey: "swizard.transportMode"), "DBI Backend")

        state.setTransportMode(.network)
        XCTAssertEqual(store.string(forKey: "swizard.transportMode"), "Network")
    }

    func testTransportModeRestoredOnLaunch() {
        let store = InMemoryPreferencesStore()
        store.setString("DBI Backend", forKey: "swizard.transportMode")

        let state = AppState(preferences: store)
        XCTAssertEqual(state.coordinator.transportMode, .dbiBackend)
    }

    func testDefaultTransportModeIsMTP() {
        let store = InMemoryPreferencesStore()
        // No saved preference
        let state = AppState(preferences: store)
        XCTAssertEqual(state.coordinator.transportMode, .mtp)
    }

    func testFailedValidationDoesNotSaveAddress() {
        let store = InMemoryPreferencesStore()
        let state = AppState(preferences: store)
        state.coordinator.transportMode = .network
        state.coordinator.ftpAddress = "invalid:abc"

        state.validateFTPAddress()

        XCTAssertNil(store.string(forKey: "swizard.ftp.lastAddress"))
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

    func testAppVersionDisplayIncludesVPrefixForReleaseVersion() {
        let store = InMemoryPreferencesStore()
        let state = AppState(
            preferences: store,
            appVersionProvider: StubVersionProvider(displayVersion: "1.2.3 (45)"),
            diagnosticsExportRunner: SpyDiagnosticsExportRunner()
        )

        XCTAssertEqual(state.appVersionDisplay, "v1.2.3 (45)")
    }

    func testAppVersionDisplayUsesDevWithoutPrefix() {
        let store = InMemoryPreferencesStore()
        let state = AppState(
            preferences: store,
            appVersionProvider: StubVersionProvider(displayVersion: "dev"),
            diagnosticsExportRunner: SpyDiagnosticsExportRunner()
        )

        XCTAssertEqual(state.appVersionDisplay, "dev")
    }

    func testAppVersionDisplayDoesNotPrefixNonNumericLabels() {
        let store = InMemoryPreferencesStore()
        let state = AppState(
            preferences: store,
            appVersionProvider: StubVersionProvider(displayVersion: "main-snapshot"),
            diagnosticsExportRunner: SpyDiagnosticsExportRunner()
        )

        XCTAssertEqual(state.appVersionDisplay, "main-snapshot")
    }

    func testExportDiagnosticsPassesContextToRunner() {
        let store = InMemoryPreferencesStore()
        let runner = SpyDiagnosticsExportRunner()
        let state = AppState(
            preferences: store,
            appVersionProvider: StubVersionProvider(displayVersion: "2.0.0"),
            diagnosticsExportRunner: runner
        )
        state.coordinator.transportMode = .network

        state.exportDiagnosticsLogs()

        XCTAssertEqual(runner.receivedRequest?.appVersion, "2.0.0")
        XCTAssertEqual(runner.receivedRequest?.transportMode, "Network")
        XCTAssertEqual(runner.receivedRequest?.installationState, "idle")
    }
}

/// Mock MTP session for tests — never prompts for password, fails immediately.
private final class MockMTPSessionForAppState: MTPSessionProtocol, @unchecked Sendable {
    func install(
        files: [PrivilegedMTPSession.FileToInstall],
        targetStorageID: UInt32?,
        onProgress: @escaping @Sendable (String, UInt64, UInt64) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws {
        onLog("Mock session — no real USB")
        throw IOUSBHostError.deviceNotFound
    }
}

private final class InMemoryPreferencesStore: PreferencesStore {
    private var boolValues: [String: Bool] = [:]
    private var stringValues: [String: String] = [:]

    func bool(forKey defaultName: String) -> Bool {
        boolValues[defaultName] ?? false
    }

    func set(_ value: Bool, forKey defaultName: String) {
        boolValues[defaultName] = value
    }

    func string(forKey defaultName: String) -> String? {
        stringValues[defaultName]
    }

    func setString(_ value: String, forKey defaultName: String) {
        stringValues[defaultName] = value
    }
}

private struct StubVersionProvider: AppVersionProviding {
    let displayVersion: String
}

private final class SpyDiagnosticsExportRunner: DiagnosticsExportRunning {
    private(set) var receivedRequest: DiagnosticsExportRequest?

    @MainActor
    func export(request: DiagnosticsExportRequest, entries: [Installer.LogEntry]) throws -> URL? {
        receivedRequest = request
        return nil
    }
}
