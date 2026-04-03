import Foundation

/// Abstraction for MTP device operations (Strategy pattern).
/// Enables MockMTPDevice for TDD without real hardware (Liskov Substitution).
public protocol MTPDeviceProtocol: Sendable {
    /// Detect and return raw MTP devices on the USB bus.
    func detectDevices() async throws -> [MTPRawDevice]

    /// Open a connection to a specific raw device.
    func open(device: MTPRawDevice) async throws

    /// Close the current connection.
    func close() async

    /// Get all storage areas on the connected device.
    func getStorages() async throws -> [MTPStorage]

    /// Get folder tree for a specific storage.
    func getFolders(storageId: UInt32) async throws -> [MTPFolder]

    /// Send a file to a specific folder on the device.
    func sendFile(
        localPath: String,
        fileName: String,
        fileSize: UInt64,
        parentFolderId: UInt32,
        storageId: UInt32,
        progress: @escaping @Sendable (UInt64, UInt64) -> Bool
    ) async throws
}

/// Represents a detected but not-yet-opened MTP device.
public struct MTPRawDevice: Sendable, Equatable {
    public let busNumber: UInt32
    public let deviceNumber: UInt8
    public let vendorId: UInt16
    public let productId: UInt16

    public init(busNumber: UInt32, deviceNumber: UInt8, vendorId: UInt16, productId: UInt16) {
        self.busNumber = busNumber
        self.deviceNumber = deviceNumber
        self.vendorId = vendorId
        self.productId = productId
    }
}

/// Immutable storage info (Value Object).
public struct MTPStorage: Sendable, Equatable, Identifiable {
    public let id: UInt32
    public let description: String
    public let freeSpaceInBytes: UInt64
    public let maxCapacity: UInt64

    public init(id: UInt32, description: String, freeSpaceInBytes: UInt64, maxCapacity: UInt64) {
        self.id = id
        self.description = description
        self.freeSpaceInBytes = freeSpaceInBytes
        self.maxCapacity = maxCapacity
    }
}

/// Immutable folder info (Value Object).
public struct MTPFolder: Sendable, Equatable, Identifiable {
    public let id: UInt32
    public let parentId: UInt32
    public let storageId: UInt32
    public let name: String

    public init(id: UInt32, parentId: UInt32, storageId: UInt32, name: String) {
        self.id = id
        self.parentId = parentId
        self.storageId = storageId
        self.name = name
    }
}
