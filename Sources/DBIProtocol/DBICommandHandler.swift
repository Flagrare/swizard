import Foundation

/// Result of handling a DBI command.
public enum DBICommandResult: Equatable, Sendable {
    case `continue`
    case exit
}

/// Command Pattern: each DBI command has its own handler (Open/Closed Principle).
public protocol DBICommandHandler: Sendable {
    var commandID: DBICommand { get }

    func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing
    ) async throws -> DBICommandResult
}
