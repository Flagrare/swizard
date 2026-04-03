import Foundation

/// Handles CMD_FILE_RANGE: reads a chunk of a file and sends it to the Switch.
/// Protocol flow: ACK the request → read payload → send RESPONSE header → read ACK → send file data.
public struct FileRangeCommandHandler: DBICommandHandler {
    public let commandID = DBICommand.fileRange

    public init() {}

    public func handle(
        header: DBIHeader,
        transport: any TransportProtocol,
        fileServer: any FileServing
    ) async throws -> DBICommandResult {
        // Step 1: ACK the FILE_RANGE request header (Switch waits for this before sending payload)
        let ack = DBIHeader(commandType: .ack, commandID: .fileRange, dataSize: header.dataSize)
        try await transport.write(ack.encoded())

        // Step 2: Read the variable-length payload the Switch now sends
        let payload = try await transport.read(maxLength: Int(header.dataSize))
        let request = try FileRangeRequest(from: payload)

        // Step 3: Read the requested file chunk
        let fileData = try fileServer.readRange(
            fileName: request.fileName,
            offset: request.rangeOffset,
            size: request.rangeSize
        )

        // Step 4: Send RESPONSE header with chunk size
        let response = DBIHeader(
            commandType: .response,
            commandID: .fileRange,
            dataSize: UInt32(fileData.count)
        )
        try await transport.write(response.encoded())

        // Step 5: Wait for Switch ACK
        _ = try await transport.read(maxLength: DBIConstants.headerSize)

        // Step 6: Send the file data
        try await transport.write(fileData)

        return .continue
    }
}
