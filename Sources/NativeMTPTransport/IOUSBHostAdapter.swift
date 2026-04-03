import Foundation
import IOKit
import IOKit.usb
import IOUSBHost

/// Adapter: wraps Apple's IOUSBHost framework for USB bulk transfers.
/// Uses DeviceSeize to ask macOS's kernel driver to release the Switch.
///
/// Implementation note: IOUSBHost on macOS requires matching both the device
/// and its interfaces as separate IOKit services. The adapter handles this
/// complexity internally.
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
        // Step 1: Find device service via IOKit
        let deviceService = try findDeviceService(vendorID: vendorID, productID: productID)
        defer { IOObjectRelease(deviceService) }

        // Step 2: Open device with DeviceSeize (asks kernel driver to release)
        let device = try openDevice(service: deviceService)
        self.hostDevice = device

        // Step 3: Configure device to expose interfaces, then find and claim one
        try device.__configure(withValue: 1, matchInterfaces: true)

        // Brief delay for interface matching
        Thread.sleep(forTimeInterval: 0.5)

        // Step 4: Find and open the first interface child service
        let interfaceService = try findInterfaceService(deviceService: deviceService)
        defer { IOObjectRelease(interfaceService) }

        let iface = try openInterface(service: interfaceService)
        self.hostInterface = iface

        // Step 5: Find bulk endpoints and create pipes
        try findBulkEndpoints(interface: iface)
    }

    private func findDeviceService(vendorID: UInt16, productID: UInt16) throws -> io_service_t {
        // Use IOUSBHostDevice (modern macOS), not kIOUSBDeviceClassName (legacy)
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = vendorID
        matching["idProduct"] = productID

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw IOUSBHostError.deviceNotFound
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        guard service != 0 else { throw IOUSBHostError.deviceNotFound }
        return service
    }

    private func openDevice(service: io_service_t) throws -> IOUSBHostDevice {
        // Try DeviceSeize first
        if let device = try? IOUSBHostDevice(
            __ioService: service,
            options: .deviceSeize,
            queue: usbQueue,
            interestHandler: nil
        ) {
            return device
        }

        // Fallback: try without flags
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

    private func findInterfaceService(deviceService: io_service_t) throws -> io_service_t {
        var iterator: io_iterator_t = 0

        guard IORegistryEntryGetChildIterator(deviceService, kIOServicePlane, &iterator) == KERN_SUCCESS else {
            throw IOUSBHostError.claimFailed("Cannot enumerate interfaces")
        }
        defer { IOObjectRelease(iterator) }

        // Find first IOUSBHostInterface child
        while true {
            let child = IOIteratorNext(iterator)
            guard child != 0 else { break }

            if IOObjectConformsTo(child, "IOUSBHostInterface") != 0 {
                return child
            }
            IOObjectRelease(child)
        }

        throw IOUSBHostError.claimFailed("No USB interface found")
    }

    private func openInterface(service: io_service_t) throws -> IOUSBHostInterface {
        if let iface = try? IOUSBHostInterface(
            __ioService: service,
            options: [],
            queue: usbQueue,
            interestHandler: nil
        ) {
            return iface
        }

        throw IOUSBHostError.claimFailed("Failed to open interface")
    }

    private func findBulkEndpoints(interface: IOUSBHostInterface) throws {
        let configDesc = interface.configurationDescriptor
        let ifaceDesc = interface.interfaceDescriptor

        // Walk endpoint descriptors using Apple's descriptor parsing API
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

            // Advance: cast endpoint back to generic descriptor header for next iteration
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
