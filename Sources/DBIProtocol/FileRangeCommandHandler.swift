import Foundation

/// Handles CMD_FILE_RANGE: reads a chunk of a file and sends it to the Switch.
/// Protocol flow: read payload → send RESPONSE header → read ACK → send file data.
public struct FileRangeCommandHandler: DBICommandHandler {
    public let commandID = DBICommand.fileRange

    public init() {}

    public func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing
    ) async throws -> DBICommandResult {
        // Read the variable-length payload
        let payload = try await transport.read(maxLength: Int(header.dataSize))
        let request = try FileRangeRequest(from: payload)

        // Read the requested file chunk
        let fileData = try fileServer.readRange(
            fileName: request.fileName,
            offset: request.rangeOffset,
            size: request.rangeSize
        )

        // Send RESPONSE header with chunk size
        let response = DBIHeader(
            commandType: .response,
            commandID: .fileRange,
            dataSize: UInt32(fileData.count)
        )
        try await transport.write(response.encoded())

        // Wait for Switch ACK
        _ = try await transport.read(maxLength: DBIConstants.headerSize)

        // Send the file data
        try await transport.write(fileData)

        return .continue
    }
}
