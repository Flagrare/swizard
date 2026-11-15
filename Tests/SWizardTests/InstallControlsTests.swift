import XCTest
@testable import SWizard
import Installer
import DBIProtocol
import USBTransport

/// Which install controls the window offers at each point of a DBI install.
@MainActor
final class InstallControlsTests: XCTestCase {

    func testClearQueueIsHiddenAndModeLockedWhileWaitingForSwitch() async throws {
        let coordinator = InstallationCoordinator(transport: SilentSwitchTransport())
        coordinator.transportMode = .dbiBackend
        let state = AppState(preferences: InMemoryPreferencesStore(), coordinator: coordinator)
        let game = try makeGame()
        defer { try? FileManager.default.removeItem(at: game) }

        coordinator.queueFiles([game])
        XCTAssertTrue(state.canClearQueue)

        coordinator.startInstallation()
        try await waitUntil { coordinator.state == .waitingForSwitch }
        XCTAssertFalse(state.canClearQueue, "Clear Queue must not be clickable mid-install")
        XCTAssertTrue(state.isTransferActive, "Mode picker is locked while the Switch is choosing")

        coordinator.cancel()
        try await waitUntil { coordinator.state == .idle }
        XCTAssertTrue(state.canClearQueue)
    }

    func testClearQueueIsUnavailableWithNothingQueued() {
        let state = AppState(preferences: InMemoryPreferencesStore())

        XCTAssertFalse(state.canClearQueue)
    }

    // MARK: - Helpers

    private func makeGame() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).nsp")
        try Data(repeating: 0, count: 10).write(to: url)
        return url
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !condition() {
            guard clock.now < deadline else {
                XCTFail("Timed out waiting for condition", file: file, line: line)
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

/// A Switch that never sends anything (user still browsing DBI's list).
private final class SilentSwitchTransport: TransportProtocol, @unchecked Sendable {
    func connect() async throws {}
    func disconnect() async throws {}
    func read(maxLength: Int) async throws -> Data {
        try await Task.sleep(for: .milliseconds(5))
        throw USBError.timeout
    }
    func write(_ data: Data) async throws {}
}
