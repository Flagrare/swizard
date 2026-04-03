import Foundation
@testable import NativeMTPTransport

/// Test double for USBBulkTransferProtocol.
/// Scripts USB conversations: queues reads, records writes.
final class MockUSBBulkTransfer: USBBulkTransferProtocol, @unchecked Sendable {
    private var readQueue: [Data] = []
    private(set) var writtenData: [Data] = []
    private(set) var isOpen = false
    private(set) var openedVendorID: UInt16?
    private(set) var openedProductID: UInt16?

    var openShouldFail = false

    func queueRead(_ data: Data) {
        readQueue.append(data)
    }

    /// Queue an MTP response container for reading.
    func queueResponse(code: UInt16, transactionID: UInt32, payload: Data = Data()) {
        let container = MTPContainer(
            type: .response,
            code: code,
            transactionID: transactionID,
            payload: payload
        )
        queueRead(container.encoded())
    }

    /// Queue an MTP data container for reading.
    func queueDataContainer(code: UInt16, transactionID: UInt32, payload: Data) {
        let container = MTPContainer(
            type: .data,
            code: code,
            transactionID: transactionID,
            payload: payload
        )
        queueRead(container.encoded())
    }

    func open(vendorID: UInt16, productID: UInt16) async throws {
        if openShouldFail {
            throw IOUSBHostError.deviceNotFound
        }
        openedVendorID = vendorID
        openedProductID = productID
        isOpen = true
    }

    func close() async {
        isOpen = false
    }

    func readBulk(maxLength: Int) async throws -> Data {
        guard !readQueue.isEmpty else {
            throw IOUSBHostError.readFailed("No more data in mock queue")
        }
        return readQueue.removeFirst()
    }

    func writeBulk(_ data: Data) async throws {
        writtenData.append(data)
    }

    /// Decode a written MTP container at a specific index.
    func writtenContainer(at index: Int) throws -> MTPContainer {
        try MTPContainer(from: writtenData[index])
    }
}

