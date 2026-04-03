import Foundation

/// Enumerates storages and folders on an MTP device.
/// Delegates all device communication to MTPDeviceProtocol (DIP).
public final class MTPFolderBrowser: Sendable {
    private let device: any MTPDeviceProtocol

    public init(device: any MTPDeviceProtocol) {
        self.device = device
    }

    /// Get all storage areas on the connected device.
    public func getStorages() async throws -> [MTPStorage] {
        try await device.getStorages()
    }

    /// Get all folders in a specific storage.
    public func getFolders(storageId: UInt32) async throws -> [MTPFolder] {
        try await device.getFolders(storageId: storageId)
    }

    /// Find a folder by name within a specific storage (case-insensitive).
    public func findInstallFolder(named name: String, storageId: UInt32) async throws -> MTPFolder? {
        let folders = try await getFolders(storageId: storageId)
        let lowered = name.lowercased()
        return folders.first { $0.name.lowercased() == lowered }
    }

    /// Search result containing both the folder and its storage ID.
    public struct InstallTarget: Sendable {
        public let folder: MTPFolder
        public let storageId: UInt32
    }

    /// Search all storages for a folder with the given name.
    public func findFirstInstallFolder(preferredName: String) async throws -> InstallTarget? {
        let storages = try await getStorages()

        for storage in storages {
            if let folder = try await findInstallFolder(named: preferredName, storageId: storage.id) {
                return InstallTarget(folder: folder, storageId: storage.id)
            }
        }

        return nil
    }
}
