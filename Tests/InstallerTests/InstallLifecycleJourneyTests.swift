import XCTest
@testable import Installer
@testable import DBIProtocol
@testable import USBTransport

/// UX journeys through a full DBI install: the real DBISession and FileServer
/// run against a scripted Switch, faked only at the USB boundary.
private typealias Step = ScriptedSwitchTransport.Step

@MainActor
final class InstallLifecycleJourneyTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() async throws {
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    // MARK: - Retry

    func testRetryAfterAFailureRestartsFromZeroAndKeepsTheLog() async throws {
        let game = try makeGame("retry.nsp", size: 64)
        let transport = ScriptedSwitchTransport(steps:
            Step.listExchange + Step.fileRange("retry.nsp", offset: 0, size: 32) + [.fail(.disconnected)]
            + Step.listExchange + Step.fileRange("retry.nsp", offset: 0, size: 64) + [.exit]
        )
        let coordinator = makeCoordinator(transport)
        coordinator.queueFiles([game])

        coordinator.startInstallation()
        try await waitUntil { if case .error = coordinator.state { true } else { false } }
        XCTAssertEqual(coordinator.progress.files.first?.transferredBytes, 32)

        coordinator.startInstallation()
        XCTAssertEqual(coordinator.progress.files.first?.transferredBytes, 0, "Retry restarts progress from 0%")

        try await waitUntil { coordinator.state == .complete }
        XCTAssertEqual(coordinator.progress.files.first?.isComplete, true)
        XCTAssertTrue(coordinator.logs.contains { $0.level == .error },
                      "The failed attempt stays in the Activity Log")
    }

    // MARK: - Clear Queue

    func testClearingTheQueueAfterAFailureKeepsTheActivityLog() async throws {
        let transport = ScriptedSwitchTransport(steps: [], failingConnects: 1)
        let coordinator = makeCoordinator(transport)
        coordinator.queueFiles([try makeGame("a.nsp"), try makeGame("b.nsp")])

        coordinator.startInstallation()
        try await waitUntil { if case .error = coordinator.state { true } else { false } }

        coordinator.clearQueue()

        XCTAssertTrue(coordinator.progress.files.isEmpty)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.logs.contains { $0.level == .error })
    }

    func testClearingTheQueueWhileTheSwitchIsChoosingChangesNothing() async throws {
        let transport = ScriptedSwitchTransport(steps:
            Step.listExchange + [.idleUntilReleased]
            + Step.fileRange("busy.nsp", offset: 0, size: 10) + [.exit]
        )
        let coordinator = makeCoordinator(transport)
        coordinator.queueFiles([try makeGame("busy.nsp")])

        coordinator.startInstallation()
        try await waitUntil { coordinator.state == .waitingForSwitch }

        coordinator.clearQueue()

        XCTAssertEqual(coordinator.progress.files.map(\.name), ["busy.nsp"])
        XCTAssertEqual(coordinator.state, .waitingForSwitch)

        transport.releaseIdle()
        try await waitUntil { coordinator.state == .complete }
    }

    func testAfterClearingOnlyNewlyQueuedGamesAreOfferedToTheSwitch() async throws {
        let transport = ScriptedSwitchTransport(
            steps: Step.listExchange + Step.fileRange("new.nsp", offset: 0, size: 10) + [.exit],
            failingConnects: 1
        )
        let coordinator = makeCoordinator(transport)
        coordinator.queueFiles([try makeGame("old.nsp")])
        coordinator.startInstallation()
        try await waitUntil { if case .error = coordinator.state { true } else { false } }

        coordinator.clearQueue()
        coordinator.queueFiles([try makeGame("new.nsp")])
        coordinator.startInstallation()
        try await waitUntil { coordinator.state == .complete }

        let offeredList = transport.writtenData.compactMap { String(data: $0, encoding: .utf8) }
        XCTAssertTrue(offeredList.contains("new.nsp\n"))
        XCTAssertFalse(offeredList.contains { $0.contains("old.nsp") }, "Cleared games must not be servable")
    }

    // MARK: - Waiting for the Switch

    func testDBIShowsWaitingForSwitchUntilTheFirstFileRequest() async throws {
        let game = try makeGame("wait.nsp", size: 64)
        let transport = ScriptedSwitchTransport(steps:
            Step.listExchange + [.idleUntilReleased]
            + Step.fileRange("wait.nsp", offset: 0, size: 32) + [.idleUntilReleased]
            + Step.fileRange("wait.nsp", offset: 32, size: 32) + [.exit]
        )
        let coordinator = makeCoordinator(transport)
        coordinator.queueFiles([game])

        coordinator.startInstallation()
        try await waitUntil { coordinator.state == .waitingForSwitch }
        XCTAssertEqual(coordinator.progress.overallFraction, 0)

        transport.releaseIdle() // user picks the game on the Switch
        try await waitUntil { coordinator.state == .transferring }

        transport.releaseIdle()
        try await waitUntil { coordinator.state == .complete }
    }

    // MARK: - Duplicates

    func testDroppingTheSameGameTwiceQueuesItOnce() async throws {
        let game = try makeGame("dup.nsp", size: 16)
        let transport = ScriptedSwitchTransport(steps:
            Step.listExchange + Step.fileRange("dup.nsp", offset: 0, size: 16) + [.exit]
        )
        let coordinator = makeCoordinator(transport)

        coordinator.queueFiles([game, game])
        coordinator.queueFiles([game])

        XCTAssertEqual(coordinator.progress.files.map(\.name), ["dup.nsp"])
        let skipped = coordinator.logs.filter { $0.level == .warning && $0.message.contains("already queued") }
        XCTAssertEqual(skipped.count, 2)

        coordinator.startInstallation()
        try await waitUntil { coordinator.state == .complete }
        XCTAssertEqual(coordinator.progress.overallFraction, 1.0)
    }

    // MARK: - End to end

    func testFullInstallServesTheFileBytesThenAcceptsANewGame() async throws {
        let content = Data((0..<96).map { UInt8($0) })
        let game = try makeGame("e2e.nsp", content: content)
        let transport = ScriptedSwitchTransport(steps:
            Step.listExchange + [.idleUntilReleased]
            + Step.fileRange("e2e.nsp", offset: 0, size: 48)
            + Step.fileRange("e2e.nsp", offset: 48, size: 48) + [.exit]
        )
        let coordinator = makeCoordinator(transport)
        coordinator.queueFiles([game])

        coordinator.startInstallation()
        try await waitUntil { coordinator.state == .waitingForSwitch }
        transport.releaseIdle()
        try await waitUntil { coordinator.state == .complete }

        XCTAssertTrue(transport.writtenData.contains(content.prefix(48)), "First half served")
        XCTAssertTrue(transport.writtenData.contains(content.suffix(48)), "Second half served")

        coordinator.queueFiles([try makeGame("next.nsp")])

        XCTAssertEqual(coordinator.state, .idle, "Dropping a new game after completion offers Install again")
        XCTAssertEqual(coordinator.progress.files.map(\.name), ["next.nsp"])
    }

    // MARK: - Helpers

    private func makeCoordinator(_ transport: ScriptedSwitchTransport) -> InstallationCoordinator {
        let coordinator = InstallationCoordinator(transport: transport, reconnectPolicy: .none)
        coordinator.transportMode = .dbiBackend
        return coordinator
    }

    private func makeGame(_ name: String, size: Int = 10) throws -> URL {
        try makeGame(name, content: Data(repeating: 0xAB, count: size))
    }

    private func makeGame(_ name: String, content: Data) throws -> URL {
        let url = tempDirectory.appendingPathComponent(name)
        try content.write(to: url)
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
