import Foundation
@testable import MTPTransport

/// Test double for MTPDeviceProtocol that records all calls and returns scripted data.
final class MockMTPDevice: MTPDeviceProtocol, @unchecked Sendable {
    var devicesToReturn: [MTPRawDevice] = []
    var storagesToReturn: [MTPStorage] = []
    var foldersToReturn: [MTPFolder] = []
    var sendFileError: MTPError?

    private(set) var detectCalled = false
    private(set) var openedDevice: MTPRawDevice?
    private(set) var closeCalled = false
    private(set) var sentFiles: [(localPath: String, fileName: String, parentFolderId: UInt32, storageId: UInt32)] = []
    private(set) var progressCallCount = 0

    func detectDevices() async throws -> [MTPRawDevice] {
        detectCalled = true
        guard !devicesToReturn.isEmpty else { throw MTPError.deviceNotFound }
        return devicesToReturn
    }

    func open(device: MTPRawDevice) async throws {
        openedDevice = device
    }

    func close() async {
        closeCalled = true
    }

    func getStorages() async throws -> [MTPStorage] {
        guard !storagesToReturn.isEmpty else { throw MTPError.noStorage }
        return storagesToReturn
    }

    func getFolders(storageId: UInt32) async throws -> [MTPFolder] {
        return foldersToReturn.filter { $0.storageId == storageId }
    }

    func sendFile(
        localPath: String,
        fileName: String,
        fileSize: UInt64,
        parentFolderId: UInt32,
        storageId: UInt32,
        progress: @escaping @Sendable (UInt64, UInt64) -> Bool
    ) async throws {
        if let error = sendFileError { throw error }

        sentFiles.append((localPath, fileName, parentFolderId, storageId))

        // Simulate progress: 0%, 50%, 100%
        _ = progress(0, fileSize)
        progressCallCount += 1
        _ = progress(fileSize / 2, fileSize)
        progressCallCount += 1
        _ = progress(fileSize, fileSize)
        progressCallCount += 1
    }
}
