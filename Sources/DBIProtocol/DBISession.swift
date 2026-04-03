import Foundation

/// Protocol state machine that dispatches incoming commands to handlers.
/// Reads headers from the Switch in a loop and delegates to the appropriate handler.
public final class DBISession: @unchecked Sendable {
    private let handlers: [DBICommand: any DBICommandHandler]
    public weak var delegate: (any DBISessionDelegate)?

    public init(handlers: [any DBICommandHandler]? = nil) {
        let handlerList = handlers ?? [
            ListCommandHandler(),
            FileRangeCommandHandler(),
            ExitCommandHandler(),
        ]
        self.handlers = Dictionary(
            uniqueKeysWithValues: handlerList.map { ($0.commandID, $0) }
        )
    }

    /// Run the protocol loop until EXIT or error.
    public func run(
        transport: any TransportProtocol,
        fileServer: any FileServing
    ) async throws {
        delegate?.sessionDidLog("DBI session started")

        while true {
            let headerData = try await transport.read(maxLength: DBIConstants.headerSize)
            let header = try DBIHeader(from: headerData)

            delegate?.sessionDidLog("Received \(header.commandID) (\(header.commandType))")

            guard let handler = handlers[header.commandID] else {
                throw DBIError.unknownCommand(header.commandID.rawValue)
            }

            let result = try await handler.handle(
                header: header,
                transport: transport,
                fileServer: fileServer,
                delegate: delegate
            )

            if result == .exit {
                delegate?.sessionDidReceiveExit()
                delegate?.sessionDidLog("DBI session ended")
                break
            }
        }
    }
}
