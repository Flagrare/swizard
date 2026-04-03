import Foundation

/// Result of handling a DBI command.
public enum DBICommandResult: Equatable, Sendable {
    case `continue`
    case exit
}

/// Command Pattern: each DBI command has its own handler (Open/Closed Principle).
/// The optional delegate allows handlers to report progress without depending on UI types.
public protocol DBICommandHandler: Sendable {
    var commandID: DBICommand { get }

    func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing,
        delegate: (any DBISessionDelegate)?
    ) async throws -> DBICommandResult
}
