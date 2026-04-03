import Foundation

/// Handles CMD_EXIT: acknowledges and signals the session to stop.
public struct ExitCommandHandler: DBICommandHandler {
    public let commandID = DBICommand.exit

    public init() {}

    public func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing,
        delegate: (any DBISessionDelegate)?
    ) async throws -> DBICommandResult {
        let response = DBIHeader(
            commandType: .response,
            commandID: .exit,
            dataSize: 0
        )
        try await transport.write(response.encoded())
        return .exit
    }
}
