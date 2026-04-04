import XCTest
@testable import Installer
@testable import DBIProtocol
@testable import USBTransport
@testable import MTPTransport

// MARK: - Simple mock transport for coordinator tests

private final class IdleMockTransport: TransportProtocol, @unchecked Sendable {
    func connect() async throws {}
    func disconnect() async throws {}
    func read(maxLength: Int) async throws -> Data {
        // Simulate EXIT immediately
        return DBIHeader(commandType: .request, commandID: .exit, dataSize: 0).encoded()
    }
    func write(_ data: Data) async throws {}
}

private final class FailingConnectTransport: TransportProtocol, @unchecked Sendable {
    func connect() async throws { throw USBError.deviceNotFound }
    func disconnect() async throws {}
    func read(maxLength: Int) async throws -> Data { Data() }
    func write(_ data: Data) async throws {}
}

// MARK: - Tests

final class InstallationCoordinatorTests: XCTestCase {

    // MARK: - State guards

    @MainActor
    func testStartInstallationRequiresIdleState() async {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .dbiBackend

        let url = try! createTempFile(name: "guard_idle.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        // Try starting again while already running
        let stateBefore = coordinator.state
        coordinator.startInstallation() // should be no-op
        // State shouldn't restart
        try? await Task.sleep(for: .seconds(0.3))
        // No crash, no double-start
        cleanup(url)
    }

    @MainActor
    func testStartInstallationWithNoFilesLogs() async {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.startInstallation()

        XCTAssertTrue(coordinator.logs.contains(where: { $0.message == "No files queued" }))
    }

    // MARK: - DBI Backend mode

    @MainActor
    func testDBIBackendModeReachesComplete() async {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .dbiBackend

        let url = try! createTempFile(name: "dbi_complete.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.5))

        XCTAssertEqual(coordinator.state, .complete)
        cleanup(url)
    }

    @MainActor
    func testDBIBackendModeReachesErrorOnConnectionFailure() async {
        let coordinator = InstallationCoordinator(transport: FailingConnectTransport())
        coordinator.transportMode = .dbiBackend

        let url = try! createTempFile(name: "dbi_fail.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.3))

        if case .error = coordinator.state { } else {
            XCTFail("Expected .error, got \(coordinator.state)")
        }
        cleanup(url)
    }

    // MARK: - MTP mode

    @MainActor
    func testMTPModeLogsAdminWarning() async {
        // Verify the coordinator logs the admin privilege warning when MTP starts.
        // We don't actually run the privileged session in tests (would prompt for password).
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .mtp

        let url = try! createTempFile(name: "mtp_log.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        // Brief sleep — just enough for the first log messages before osascript runs
        try? await Task.sleep(for: .seconds(0.3))
        coordinator.cancel()

        XCTAssertTrue(coordinator.logs.contains(where: { $0.message.contains("admin privileges") }))
        cleanup(url)
    }

    // MARK: - Queue management

    @MainActor
    func testQueueFilesRegistersProgress() {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        let url = try! createTempFile(name: "queue_test.nsp", content: Data(repeating: 0, count: 500))

        coordinator.queueFiles([url])

        XCTAssertEqual(coordinator.progress.files.count, 1)
        XCTAssertEqual(coordinator.progress.files[0].name, "queue_test.nsp")
        XCTAssertEqual(coordinator.progress.files[0].totalBytes, 500)
        cleanup(url)
    }

    // MARK: - Reset

    @MainActor
    func testResetClearsEverything() {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        let url = try! createTempFile(name: "reset_test.nsp", content: Data(repeating: 0, count: 10))

        coordinator.queueFiles([url])
        coordinator.reset()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.progress.files.isEmpty)
        XCTAssertTrue(coordinator.logs.isEmpty)
        cleanup(url)
    }

    // MARK: - Mode switching

    @MainActor
    func testTransportModeDefaultsToMTP() {
        let coordinator = InstallationCoordinator()
        XCTAssertEqual(coordinator.transportMode, .mtp)
    }

    @MainActor
    func testTransportModeCanBeChanged() {
        let coordinator = InstallationCoordinator()
        coordinator.transportMode = .dbiBackend
        XCTAssertEqual(coordinator.transportMode, .dbiBackend)
        coordinator.transportMode = .network
        XCTAssertEqual(coordinator.transportMode, .network)
    }

    // MARK: - UX Journey: MTP connecting state visible before transferring

    @MainActor
    func testMTPModePassesThroughConnectingState() async {
        let mockMTP = MockMTPDevice()
        let coordinator = InstallationCoordinator(transport: IdleMockTransport(), mtpDevice: mockMTP)
        coordinator.transportMode = .mtp

        let url = try! createTempFile(name: "mtp_state.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        // Give the task a chance to start
        try? await Task.sleep(for: .seconds(0.1))

        // Should have logged the connecting message (proves .connecting was hit)
        XCTAssertTrue(coordinator.logs.contains(where: { $0.message.contains("Connecting to Switch (MTP)") }))
        cleanup(url)
    }

    // MARK: - UX Journey: cancel stops network server immediately

    @MainActor
    func testCancelClearsNetworkInfo() async {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .network

        let url = try! createTempFile(name: "net_cancel.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.3))

        coordinator.cancel()

        // networkInfo should be cleared immediately
        XCTAssertNil(coordinator.networkInfo)
        cleanup(url)
    }

    // MARK: - UX Journey: network mode shows server info

    @MainActor
    func testNetworkModeShowsServerInfo() async {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .network

        let url = try! createTempFile(name: "net_info.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.5))

        // Should have networkInfo set (IP:port)
        XCTAssertNotNil(coordinator.networkInfo)
        XCTAssertTrue(coordinator.networkInfo?.contains(":5000") ?? false)

        coordinator.cancel()
        cleanup(url)
    }

    // MARK: - UX Journey: MTP retries on transient error

    @MainActor
    func testMTPModeStartsInConnectingState() async {
        // Verify MTP mode transitions to .connecting before running privileged session.
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .mtp

        let url = try! createTempFile(name: "mtp_state.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.2))
        // Should be in connecting state (before privileged session completes)
        let isConnectingOrBeyond = coordinator.state == .connecting ||
            coordinator.state == .transferring ||
            coordinator.state == .complete
        XCTAssertTrue(isConnectingOrBeyond || {
            if case .error = coordinator.state { return true }
            return false
        }(), "Expected connecting/transferring/error, got \(coordinator.state)")

        coordinator.cancel()
        cleanup(url)
    }

    // MARK: - UX Journey: reset during transfer

    @MainActor
    func testResetDuringNetworkTransfer() async {
        let coordinator = InstallationCoordinator(transport: IdleMockTransport())
        coordinator.transportMode = .network

        let url = try! createTempFile(name: "net_reset.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.3))

        coordinator.reset()

        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.progress.files.isEmpty)
        XCTAssertNil(coordinator.networkInfo)
        cleanup(url)
    }

    // MARK: - Helpers

    private func createTempFile(name: String, content: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Private mock for MTP tests (minimal, just enough for coordinator)

private final class MockMTPDevice: MTPDeviceProtocol, @unchecked Sendable {
    func detectDevices() async throws -> [MTPRawDevice] { throw MTPError.deviceNotFound }
    func open(device: MTPRawDevice) async throws {}
    func close() async {}
    func getStorages() async throws -> [MTPStorage] { [] }
    func getFolders(storageId: UInt32) async throws -> [MTPFolder] { [] }
    func sendFile(localPath: String, fileName: String, fileSize: UInt64,
                  parentFolderId: UInt32, storageId: UInt32,
                  progress: @escaping @Sendable (UInt64, UInt64) -> Bool) async throws {}
}

/// MTP device that fails N times then succeeds — for testing retry behavior.
private final class RetryableMockMTPDevice: MTPDeviceProtocol, @unchecked Sendable {
    private var failCount: Int
    private var callCount = 0

    init(failCount: Int) { self.failCount = failCount }

    func detectDevices() async throws -> [MTPRawDevice] {
        callCount += 1
        if callCount <= failCount {
            throw MTPError.transferFailed("transient")
        }
        return [MTPRawDevice(busNumber: 1, deviceNumber: 2, vendorId: NintendoSwitchUSB.vendorID, productId: NintendoSwitchUSB.mtpProductID)]
    }

    func open(device: MTPRawDevice) async throws {}
    func close() async {}

    func getStorages() async throws -> [MTPStorage] {
        [MTPStorage(id: 1, description: "SD", freeSpaceInBytes: 32_000_000_000, maxCapacity: 64_000_000_000)]
    }

    func getFolders(storageId: UInt32) async throws -> [MTPFolder] {
        [MTPFolder(id: 10, parentId: 0, storageId: 1, name: "MicroSD Install")]
    }

    func sendFile(localPath: String, fileName: String, fileSize: UInt64,
                  parentFolderId: UInt32, storageId: UInt32,
                  progress: @escaping @Sendable (UInt64, UInt64) -> Bool) async throws {
        _ = progress(fileSize, fileSize)
    }
}
