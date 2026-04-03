import Foundation

/// Sends files to an MTP device via MTPDeviceProtocol.
/// SRP: only handles file transfer — no device discovery or folder browsing.
public final class MTPFileTransfer: Sendable {
    private let device: any MTPDeviceProtocol

    public init(device: any MTPDeviceProtocol) {
        self.device = device
    }

    /// Send a single file to the device with progress reporting.
    /// Progress closure returns false to cancel.
    public func sendFile(
        localPath: String,
        fileName: String,
        fileSize: UInt64,
        parentFolderId: UInt32,
        storageId: UInt32,
        progress: @escaping @Sendable (UInt64, UInt64) -> Bool
    ) async throws {
        try await device.sendFile(
            localPath: localPath,
            fileName: fileName,
            fileSize: fileSize,
            parentFolderId: parentFolderId,
            storageId: storageId,
            progress: progress
        )
    }
}
