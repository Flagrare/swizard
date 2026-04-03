import XCTest
@testable import Installer
@testable import DBIProtocol
@testable import USBTransport

/// Mock transport that disconnects on the Nth read, then works normally.
final class DisconnectingMockTransport: TransportProtocol, @unchecked Sendable {
    private var readCount = 0
    private let disconnectAfterRead: Int
    private var hasDisconnected = false
    private let readData: [Data]
    private var readIndex = 0

    init(disconnectAfterRead: Int, readData: [Data]) {
        self.disconnectAfterRead = disconnectAfterRead
        self.readData = readData
    }

    func connect() async throws {}
    func disconnect() async throws {}

    func read(maxLength: Int) async throws -> Data {
        readCount += 1
        if readCount == disconnectAfterRead && !hasDisconnected {
            hasDisconnected = true
            readIndex = 0 // Reset for reconnect
            readCount = 0
            throw USBError.disconnected
        }
        guard readIndex < readData.count else {
            throw USBError.disconnected
        }
        let data = readData[readIndex]
        readIndex += 1
        return data
    }

    func write(_ data: Data) async throws {}
}

/// Transport that always disconnects on read.
final class AlwaysDisconnectTransport: TransportProtocol, @unchecked Sendable {
    private(set) var connectCount = 0

    func connect() async throws { connectCount += 1 }
    func disconnect() async throws {}

    func read(maxLength: Int) async throws -> Data {
        throw USBError.disconnected
    }

    func write(_ data: Data) async throws {}
}

final class ReconnectPolicyTests: XCTestCase {

    func testDefaultPolicyHasThreeAttempts() {
        let policy = ReconnectPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseDelay, 2.0)
    }

    func testNonePolicyHasZeroAttempts() {
        let policy = ReconnectPolicy.none
        XCTAssertEqual(policy.maxAttempts, 0)
    }
}

final class ReconnectBehaviorTests: XCTestCase {

    @MainActor
    func testCoordinatorReachesErrorAfterExhaustingReconnects() async {
        let transport = AlwaysDisconnectTransport()
        let policy = ReconnectPolicy(maxAttempts: 2, baseDelay: 0)
        let coordinator = InstallationCoordinator(transport: transport, reconnectPolicy: policy)
        coordinator.transportMode = .dbiBackend

        let url = try! createTempFile(name: "reconnect_test.nsp", content: Data(repeating: 0, count: 100))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        // Wait for the coordinator to finish
        try? await Task.sleep(for: .seconds(0.5))

        if case .error = coordinator.state {
            // Expected: error after exhausting reconnects
        } else {
            XCTFail("Expected .error state, got \(coordinator.state)")
        }

        // Should have connected 3 times: 1 initial + 2 reconnects
        XCTAssertEqual(transport.connectCount, 3)

        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    func testCoordinatorDoesNotReconnectWithNonePolicy() async {
        let transport = AlwaysDisconnectTransport()
        let policy = ReconnectPolicy.none
        let coordinator = InstallationCoordinator(transport: transport, reconnectPolicy: policy)
        coordinator.transportMode = .dbiBackend

        let url = try! createTempFile(name: "no_reconnect.nsp", content: Data(repeating: 0, count: 100))
        coordinator.queueFiles([url])
        coordinator.startInstallation()

        try? await Task.sleep(for: .seconds(0.3))

        if case .error = coordinator.state { } else {
            XCTFail("Expected .error state, got \(coordinator.state)")
        }

        // Only 1 connect attempt, no reconnects
        XCTAssertEqual(transport.connectCount, 1)

        try? FileManager.default.removeItem(at: url)
    }

    private func createTempFile(name: String, content: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try content.write(to: url)
        return url
    }
}
