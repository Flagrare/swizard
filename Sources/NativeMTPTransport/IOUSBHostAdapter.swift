import Foundation
import IOKit
import IOKit.usb
import IOUSBHost
import DBIProtocol

/// Adapter: wraps Apple's IOUSBHost framework for USB bulk transfers.
/// Uses a privileged helper (admin password prompt) to claim the device
/// from macOS's kernel driver via DeviceCapture.
public final class IOUSBHostAdapter: USBBulkTransferProtocol, @unchecked Sendable {
    private let usbQueue = DispatchQueue(label: "com.swizard.iousbhost", qos: .userInitiated)
    private var hostDevice: IOUSBHostDevice?
    private var hostInterface: IOUSBHostInterface?
    private var inPipe: IOUSBHostPipe?
    private var outPipe: IOUSBHostPipe?

    public init() {}

    public func open(vendorID: UInt16, productID: UInt16) async throws {
        // Step 1: Verify device exists
        guard USBDeviceScanner.findDevice(vendorID: vendorID, productID: productID) != nil else {
            throw IOUSBHostError.deviceNotFound
        }

        // Step 2: Use privileged helper to release kernel drivers via DeviceCapture
        // This prompts the user for admin password once
        try await PrivilegedUSBClaim.claimDevice(vendorID: vendorID, productID: productID)

        // Step 3: Brief wait for device re-enumeration after DeviceCapture destroy
        try await Task.sleep(for: .seconds(1.5))

        // Step 4: Now open the device normally — drivers should be unloaded
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            usbQueue.async { [self] in
                do {
                    try self.openAfterClaim(vendorID: vendorID, productID: productID)
                    continuation.resume()
                } catch {
                    self.cleanup()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func close() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            usbQueue.async { [self] in
                self.cleanup()
                continuation.resume()
            }
        }
    }

    public func readBulk(maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            usbQueue.async { [self] in
                guard let inPipe = self.inPipe else {
                    continuation.resume(throwing: IOUSBHostError.readFailed("No IN pipe"))
                    return
                }
                do {
                    let buffer = NSMutableData(length: maxLength)!
                    var bytesRead: Int = 0
                    try inPipe.__sendIORequest(
                        with: buffer,
                        bytesTransferred: &bytesRead,
                        completionTimeout: 5.0
                    )
                    continuation.resume(returning: Data(buffer.prefix(bytesRead)))
                } catch {
                    continuation.resume(throwing: IOUSBHostError.readFailed(error.localizedDescription))
                }
            }
        }
    }

    public func writeBulk(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            usbQueue.async { [self] in
                guard let outPipe = self.outPipe else {
                    continuation.resume(throwing: IOUSBHostError.writeFailed("No OUT pipe"))
                    return
                }
                do {
                    let mutableData = NSMutableData(data: data)
                    var bytesWritten: Int = 0
                    try outPipe.__sendIORequest(
                        with: mutableData,
                        bytesTransferred: &bytesWritten,
                        completionTimeout: 5.0
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: IOUSBHostError.writeFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Private

    private func openAfterClaim(vendorID: UInt16, productID: UInt16) throws {
        // Re-find device (service ID may have changed after DeviceCapture reset)
        guard let deviceInfo = USBDeviceScanner.findDevice(vendorID: vendorID, productID: productID) else {
            throw IOUSBHostError.deviceNotFound
        }

        // Open device — after privileged claim, DeviceSeize should work
        let device: IOUSBHostDevice
        if let seized = try? IOUSBHostDevice(
            __ioService: deviceInfo.service,
            options: .deviceSeize,
            queue: usbQueue,
            interestHandler: nil
        ) {
            device = seized
        } else if let plain = try? IOUSBHostDevice(
            __ioService: deviceInfo.service,
            options: [],
            queue: usbQueue,
            interestHandler: nil
        ) {
            device = plain
        } else {
            throw IOUSBHostError.seizeRejected
        }
        self.hostDevice = device

        // Configure without matching to prevent kernel re-claiming
        try device.__configure(withValue: 1, matchInterfaces: false)
        Thread.sleep(forTimeInterval: 0.5)

        // Find and open interface
        guard let ifaceService = findInterfaceChild(deviceService: deviceInfo.service) else {
            throw IOUSBHostError.claimFailed("No interface appeared after configure")
        }

        let iface: IOUSBHostInterface
        if let opened = try? IOUSBHostInterface(
            __ioService: ifaceService,
            options: [],
            queue: usbQueue,
            interestHandler: nil
        ) {
            iface = opened
        } else {
            IOObjectRelease(ifaceService)
            throw IOUSBHostError.claimFailed("Failed to open interface")
        }
        IOObjectRelease(ifaceService)
        self.hostInterface = iface

        // Find bulk endpoints
        try findBulkEndpoints(interface: iface)
    }

    private func findInterfaceChild(deviceService: io_service_t) -> io_service_t? {
        let allDevices = USBDeviceScanner.findAllDevices()
        guard let deviceInfo = allDevices.first(where: {
            $0.vendorID == NintendoSwitchUSB.vendorID && $0.productID == NintendoSwitchUSB.mtpProductID
        }) else { return nil }

        var iterator: io_iterator_t = 0
        guard IORegistryEntryGetChildIterator(deviceInfo.service, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let child = IOIteratorNext(iterator)
            guard child != 0 else { break }
            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 {
                return child
            }
            IOObjectRelease(child)
        }
        return nil
    }

    private func findBulkEndpoints(interface: IOUSBHostInterface) throws {
        let configDesc = interface.configurationDescriptor
        let ifaceDesc = interface.interfaceDescriptor

        var currentHeader: UnsafePointer<IOUSBDescriptorHeader>?
        var ep = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, currentHeader)

        while let endpoint = ep {
            let address = endpoint.pointee.bEndpointAddress
            let transferType = endpoint.pointee.bmAttributes & 0x03

            if transferType == 2 { // Bulk
                if address & 0x80 != 0, inPipe == nil {
                    self.inPipe = try? interface.copyPipe(withAddress: Int(address))
                } else if address & 0x80 == 0, outPipe == nil {
                    self.outPipe = try? interface.copyPipe(withAddress: Int(address))
                }
            }

            currentHeader = UnsafeRawPointer(endpoint).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
            ep = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, currentHeader)
        }

        guard inPipe != nil, outPipe != nil else {
            throw IOUSBHostError.claimFailed("Bulk endpoints not found")
        }
    }

    private func cleanup() {
        inPipe = nil
        outPipe = nil
        hostInterface?.destroy()
        hostInterface = nil
        hostDevice?.destroy()
        hostDevice = nil
    }

    deinit { cleanup() }
}
