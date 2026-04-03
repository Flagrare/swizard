import Foundation

/// Handles CMD_LIST: sends the list of available files to the Switch.
/// Protocol flow: send RESPONSE header with size → read ACK → send file list bytes.
public struct ListCommandHandler: DBICommandHandler {
    public let commandID = DBICommand.list

    public init() {}

    public func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing
    ) async throws -> DBICommandResult {
        let fileListString = fileServer.fileList()
        let fileListData = Data(fileListString.utf8)

        // Send RESPONSE header with file list size
        let response = DBIHeader(
            commandType: .response,
            commandID: .list,
            dataSize: UInt32(fileListData.count)
        )
        try await transport.write(response.encoded())

        // Wait for Switch ACK
        _ = try await transport.read(maxLength: DBIConstants.headerSize)

        // Send the file list bytes
        try await transport.write(fileListData)

        return .continue
    }
}
