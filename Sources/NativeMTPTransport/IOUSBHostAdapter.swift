import Foundation
import IOKit
import IOKit.usb
import IOUSBHost
import DBIProtocol

/// Adapter: wraps Apple's IOUSBHost framework for USB bulk transfers.
/// Uses DeviceSeize to ask macOS's kernel driver to release the Switch.
public final class IOUSBHostAdapter: USBBulkTransferProtocol, @unchecked Sendable {
    private let usbQueue = DispatchQueue(label: "com.swizard.iousbhost", qos: .userInitiated)
    private var hostDevice: IOUSBHostDevice?
    private var hostInterface: IOUSBHostInterface?
    private var inPipe: IOUSBHostPipe?
    private var outPipe: IOUSBHostPipe?

    public init() {}

    public func open(vendorID: UInt16, productID: UInt16) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            usbQueue.async { [self] in
                do {
                    try self.findAndOpen(vendorID: vendorID, productID: productID)
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

    private func findAndOpen(vendorID: UInt16, productID: UInt16) throws {
        // Step 1: Find device via scanner
        guard let deviceInfo = USBDeviceScanner.findDevice(vendorID: vendorID, productID: productID) else {
            throw IOUSBHostError.deviceNotFound
        }

        // Step 2: Open device — try DeviceSeize first, then plain open
        let device = try openDevice(service: deviceInfo.service)
        self.hostDevice = device

        // Step 3: Configure device WITHOUT auto-matching interfaces
        // matchInterfaces:false prevents AppleUSBHostCompositeDevice from claiming
        try device.__configure(withValue: 1, matchInterfaces: false)

        // Step 4: Wait for interface services to appear
        Thread.sleep(forTimeInterval: 1.0)

        // Step 5: Find interface child — re-scan IORegistry since configure created new services
        guard let ifaceService = findInterfaceChild(deviceService: deviceInfo.service) else {
            throw IOUSBHostError.claimFailed("No interface appeared after configure")
        }

        // Step 6: Open interface with DeviceSeize to claim from any driver
        let iface: IOUSBHostInterface
        if let seized = try? IOUSBHostInterface(
            __ioService: ifaceService,
            options: .deviceSeize,
            queue: usbQueue,
            interestHandler: nil
        ) {
            iface = seized
        } else if let plain = try? IOUSBHostInterface(
            __ioService: ifaceService,
            options: [],
            queue: usbQueue,
            interestHandler: nil
        ) {
            iface = plain
        } else {
            IOObjectRelease(ifaceService)
            throw IOUSBHostError.claimFailed("Failed to open interface")
        }
        IOObjectRelease(ifaceService)
        self.hostInterface = iface

        // Step 7: Find bulk endpoints
        try findBulkEndpoints(interface: iface)
    }

    private func openDevice(service: io_service_t) throws -> IOUSBHostDevice {
        if let device = try? IOUSBHostDevice(
            __ioService: service,
            options: .deviceSeize,
            queue: usbQueue,
            interestHandler: nil
        ) {
            return device
        }

        if let device = try? IOUSBHostDevice(
            __ioService: service,
            options: [],
            queue: usbQueue,
            interestHandler: nil
        ) {
            return device
        }

        throw IOUSBHostError.seizeRejected
    }

    private func findInterfaceChild(deviceService: io_service_t) -> io_service_t? {
        // Re-scan for the device (it may have a new ID after configure)
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
