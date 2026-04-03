import Foundation

/// Abstraction for USB bulk transfers (Strategy pattern).
/// Enables MockUSBBulkTransfer for TDD without real hardware.
public protocol USBBulkTransferProtocol: Sendable {
    /// Find and open a USB device by Vendor ID and Product ID.
    func open(vendorID: UInt16, productID: UInt16) async throws

    /// Close the USB device.
    func close() async

    /// Read data from the bulk IN endpoint.
    func readBulk(maxLength: Int) async throws -> Data

    /// Write data to the bulk OUT endpoint.
    func writeBulk(_ data: Data) async throws
}
