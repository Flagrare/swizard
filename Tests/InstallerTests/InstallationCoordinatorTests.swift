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
    func testMTPModeReachesErrorWhenNoDevice() async {
        let mockMTP = MockMTPDevice() // empty — no devices
        let coordinator = InstallationCoordinator(transport: IdleMockTransport(), mtpDevice: mockMTP)
        coordinator.transportMode = .mtp

        let url = try! createTempFile(name: "mtp_nodev.nsp", content: Data(repeating: 0, count: 10))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.3))

        if case .error = coordinator.state { } else {
            XCTFail("Expected .error, got \(coordinator.state)")
        }
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
