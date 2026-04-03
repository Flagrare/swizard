import Foundation

/// Facade: orchestrates the full MTP install flow.
/// detect device → open → find install folder → send each file → close
/// Composes MTPFolderBrowser + MTPDeviceProtocol.sendFile (SRP per component).
public final class MTPInstaller: Sendable {
    private let device: any MTPDeviceProtocol
    private let installFolderName: String

    public init(device: any MTPDeviceProtocol, installFolderName: String = "MicroSD Install") {
        self.device = device
        self.installFolderName = installFolderName
    }

    /// Install files to the Switch via MTP.
    /// Progress closure receives (fileName, bytesSent, totalBytes) and returns false to cancel.
    public func install(
        files: [(localPath: String, fileName: String, fileSize: UInt64)],
        progress: @escaping @Sendable (String, UInt64, UInt64) -> Bool
    ) async throws {
        // Step 1: Detect and open device
        let rawDevices = try await device.detectDevices()
        guard let firstDevice = rawDevices.first else {
            throw MTPError.deviceNotFound
        }

        try await device.open(device: firstDevice)

        do {
            // Step 2: Find install folder
            let browser = MTPFolderBrowser(device: device)
            guard let target = try await browser.findFirstInstallFolder(preferredName: installFolderName) else {
                await device.close()
                throw MTPError.installFolderNotFound(installFolderName)
            }

            // Step 3: Send each file directly via device protocol
            for file in files {
                try await device.sendFile(
                    localPath: file.localPath,
                    fileName: file.fileName,
                    fileSize: file.fileSize,
                    parentFolderId: target.folder.id,
                    storageId: target.storageId,
                    progress: { sent, total in
                        progress(file.fileName, sent, total)
                    }
                )
            }

            await device.close()
        } catch {
            await device.close()
            throw error
        }
    }
}
