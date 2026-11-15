import Foundation
@testable import DBIProtocol
@testable import USBTransport

/// Plays the Switch's side of a DBI conversation over a fake USB link.
/// Only the USB boundary is faked; the real DBISession and FileServer run against it.
final class ScriptedSwitchTransport: TransportProtocol, @unchecked Sendable {
    enum Step {
        case data(Data)
        /// Switch sits idle (user browsing / Switch busy) until `releaseIdle()` is called.
        case idleUntilReleased
        case fail(USBError)
    }

    private let lock = NSLock()
    private var steps: [Step]
    private var idleReleased = false
    private var connectFailuresRemaining: Int
    private var writes: [Data] = []

    init(steps: [Step], failingConnects: Int = 0) {
        self.steps = steps
        self.connectFailuresRemaining = failingConnects
    }

    /// Lets the Switch leave the current idle step (e.g. the user picked a game).
    func releaseIdle() {
        lock.withLock { idleReleased = true }
    }

    /// Everything SWizard wrote to the Switch, in order.
    var writtenData: [Data] { lock.withLock { writes } }

    func connect() async throws {
        let shouldFail = lock.withLock {
            guard connectFailuresRemaining > 0 else { return false }
            connectFailuresRemaining -= 1
            return true
        }
        if shouldFail { throw USBError.deviceNotFound }
    }

    func disconnect() async throws {}

    func read(maxLength: Int) async throws -> Data {
        switch nextStep() {
        case .none:
            throw USBError.disconnected
        case .idleUntilReleased:
            try await Task.sleep(for: .milliseconds(5))
            throw USBError.timeout
        case .fail(let error):
            throw error
        case .data(let data):
            return data
        }
    }

    /// Pops the next step, skipping past an idle step once it has been released.
    private func nextStep() -> Step? {
        lock.withLock {
            if case .idleUntilReleased = steps.first, idleReleased {
                steps.removeFirst()
                idleReleased = false
            }
            guard let first = steps.first else { return nil }
            if case .idleUntilReleased = first { return first }
            return steps.removeFirst()
        }
    }

    func write(_ data: Data) async throws {
        lock.withLock { writes.append(data) }
    }
}

// MARK: - Conversation building blocks

extension ScriptedSwitchTransport.Step {
    static func header(_ type: DBICommandType, _ command: DBICommand, size: UInt32 = 0) -> Self {
        .data(DBIHeader(commandType: type, commandID: command, dataSize: size).encoded())
    }

    /// Switch asks for the file list and ACKs our response.
    static var listExchange: [Self] {
        [header(.request, .list), header(.ack, .list)]
    }

    /// Switch requests `size` bytes of `fileName` at `offset`, then ACKs our response header.
    static func fileRange(_ fileName: String, offset: UInt64, size: UInt32) -> [Self] {
        let nameData = Data(fileName.utf8)
        var payload = Data()
        payload.appendLittleEndian(size)
        payload.appendLittleEndian(offset)
        payload.appendLittleEndian(UInt32(nameData.count))
        payload.append(nameData)
        return [
            header(.request, .fileRange, size: UInt32(payload.count)),
            .data(payload),
            header(.ack, .fileRange),
        ]
    }

    static var exit: Self { header(.request, .exit) }
}
