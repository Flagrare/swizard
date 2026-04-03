import Foundation

/// Handles CMD_LIST: sends the list of available files to the Switch.
/// Protocol flow: send RESPONSE header with size → read ACK → send file list bytes.
public struct ListCommandHandler: DBICommandHandler {
    public let commandID = DBICommand.list

    public init() {}

    public func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing,
        delegate: (any DBISessionDelegate)?
    ) async throws -> DBICommandResult {
        let fileListString = fileServer.fileList()
        let fileListData = Data(fileListString.utf8)

        let response = DBIHeader(
            commandType: .response,
            commandID: .list,
            dataSize: UInt32(fileListData.count)
        )
        try await transport.write(response.encoded())

        _ = try await transport.read(maxLength: DBIConstants.headerSize)

        try await transport.write(fileListData)

        delegate?.sessionDidLog("Sent file list: \(fileListString.trimmingCharacters(in: .newlines))")

        return .continue
    }
}
