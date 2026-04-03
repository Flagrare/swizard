import Foundation
import CLibMTP

/// Adapter: wraps libmtp's blocking C API into Swift async MTPDeviceProtocol.
/// All libmtp calls run on a dedicated serial DispatchQueue (same pattern as USBTransport).
public final class MTPDevice: MTPDeviceProtocol, @unchecked Sendable {
    private let mtpQueue = DispatchQueue(label: "com.swizard.mtp", qos: .userInitiated)
    private var device: UnsafeMutablePointer<LIBMTP_mtpdevice_t>?

    public init() {
        LIBMTP_Init()
    }

    public func detectDevices() async throws -> [MTPRawDevice] {
        try await withCheckedThrowingContinuation { continuation in
            mtpQueue.async {
                var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>?
                var count: Int32 = 0

                let result = LIBMTP_Detect_Raw_Devices(&rawDevices, &count)
                guard result == LIBMTP_ERROR_NONE else {
                    continuation.resume(throwing: MTPError.deviceNotFound)
                    return
                }

                defer { free(rawDevices) }

                var devices: [MTPRawDevice] = []
                for i in 0..<Int(count) {
                    let raw = rawDevices![i]
                    devices.append(MTPRawDevice(
                        busNumber: UInt32(raw.bus_location),
                        deviceNumber: raw.devnum,
                        vendorId: raw.device_entry.vendor_id,
                        productId: raw.device_entry.product_id
                    ))
                }

                continuation.resume(returning: devices)
            }
        }
    }

    public func open(device rawDevice: MTPRawDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            mtpQueue.async { [self] in
                var rawDevices: UnsafeMutablePointer<LIBMTP_raw_device_t>?
                var count: Int32 = 0

                let result = LIBMTP_Detect_Raw_Devices(&rawDevices, &count)
                guard result == LIBMTP_ERROR_NONE, let rawDevices, count > 0 else {
                    continuation.resume(throwing: MTPError.deviceNotFound)
                    return
                }

                defer { free(rawDevices) }

                // Find the matching device by bus location + device number
                var found: UnsafeMutablePointer<LIBMTP_raw_device_t>?
                for i in 0..<Int(count) {
                    let raw = rawDevices[i]
                    if raw.devnum == rawDevice.deviceNumber &&
                       UInt32(raw.bus_location) == rawDevice.busNumber {
                        found = rawDevices + i
                        break
                    }
                }

                guard let found else {
                    continuation.resume(throwing: MTPError.deviceNotFound)
                    return
                }

                guard let dev = LIBMTP_Open_Raw_Device_Uncached(found) else {
                    continuation.resume(throwing: MTPError.connectionFailed("Failed to open MTP device"))
                    return
                }

                self.device = dev
                continuation.resume()
            }
        }
    }

    public func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            mtpQueue.async { [self] in
                if let device = self.device {
                    LIBMTP_Release_Device(device)
                    self.device = nil
                }
                continuation.resume()
            }
        }
    }

    public func getStorages() async throws -> [MTPStorage] {
        try await withCheckedThrowingContinuation { continuation in
            mtpQueue.async { [self] in
                guard let device = self.device else {
                    continuation.resume(throwing: MTPError.deviceNotFound)
                    return
                }

                let result = LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED)
                guard result == 0 else {
                    continuation.resume(throwing: MTPError.noStorage)
                    return
                }

                var storages: [MTPStorage] = []
                var storage = device.pointee.storage
                while let s = storage {
                    let desc = s.pointee.StorageDescription.map { String(cString: $0) } ?? "Unknown"
                    storages.append(MTPStorage(
                        id: s.pointee.id,
                        description: desc,
                        freeSpaceInBytes: s.pointee.FreeSpaceInBytes,
                        maxCapacity: s.pointee.MaxCapacity
                    ))
                    storage = s.pointee.next
                }

                continuation.resume(returning: storages)
            }
        }
    }

    public func getFolders(storageId: UInt32) async throws -> [MTPFolder] {
        try await withCheckedThrowingContinuation { continuation in
            mtpQueue.async { [self] in
                guard let device = self.device else {
                    continuation.resume(throwing: MTPError.deviceNotFound)
                    return
                }

                guard let rootFolder = LIBMTP_Get_Folder_List_For_Storage(device, storageId) else {
                    continuation.resume(returning: [])
                    return
                }

                defer { LIBMTP_destroy_folder_t(rootFolder) }

                var folders: [MTPFolder] = []
                Self.flattenFolderTree(rootFolder, into: &folders)
                continuation.resume(returning: folders)
            }
        }
    }

    public func sendFile(
        localPath: String,
        fileName: String,
        fileSize: UInt64,
        parentFolderId: UInt32,
        storageId: UInt32,
        progress: @escaping @Sendable (UInt64, UInt64) -> Bool
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            mtpQueue.async { [self] in
                guard let device = self.device else {
                    continuation.resume(throwing: MTPError.deviceNotFound)
                    return
                }

                let fileMetadata = LIBMTP_new_file_t()!
                fileMetadata.pointee.filename = strdup(fileName)
                fileMetadata.pointee.filesize = fileSize
                fileMetadata.pointee.filetype = LIBMTP_FILETYPE_UNKNOWN
                fileMetadata.pointee.parent_id = parentFolderId
                fileMetadata.pointee.storage_id = storageId

                defer { LIBMTP_destroy_file_t(fileMetadata) }

                // Bridge Swift closure to C callback
                let context = ProgressContext(callback: progress)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                let result = LIBMTP_Send_File_From_File(
                    device,
                    localPath,
                    fileMetadata,
                    { sent, total, data in
                        guard let data else { return 0 }
                        let ctx = Unmanaged<ProgressContext>.fromOpaque(data).takeUnretainedValue()
                        return ctx.callback(sent, total) ? 0 : 1
                    },
                    contextPtr
                )

                Unmanaged<ProgressContext>.fromOpaque(contextPtr).release()

                if result != 0 {
                    continuation.resume(throwing: MTPError.transferFailed("libmtp error code: \(result)"))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    // MARK: - Private

    private static func flattenFolderTree(
        _ folder: UnsafeMutablePointer<LIBMTP_folder_t>,
        into result: inout [MTPFolder]
    ) {
        let name = folder.pointee.name.map { String(cString: $0) } ?? ""
        result.append(MTPFolder(
            id: folder.pointee.folder_id,
            parentId: folder.pointee.parent_id,
            storageId: folder.pointee.storage_id,
            name: name
        ))

        if let child = folder.pointee.child {
            flattenFolderTree(child, into: &result)
        }
        if let sibling = folder.pointee.sibling {
            flattenFolderTree(sibling, into: &result)
        }
    }
}

/// Bridges Swift closure to C progress callback via Unmanaged pointer.
private final class ProgressContext: @unchecked Sendable {
    let callback: @Sendable (UInt64, UInt64) -> Bool
    init(callback: @escaping @Sendable (UInt64, UInt64) -> Bool) {
        self.callback = callback
    }
}
