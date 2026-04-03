import Foundation
import IOKit
import IOKit.usb

/// Scans all connected USB devices via IOKit registry.
/// Used for device discovery and debugging when known PIDs don't match.
public enum USBDeviceScanner {
    public struct USBDeviceInfo: Sendable, CustomStringConvertible {
        public let vendorID: UInt16
        public let productID: UInt16
        public let name: String
        public let service: io_service_t

        public var description: String {
            String(format: "%@ (VID: 0x%04X, PID: 0x%04X)", name, vendorID, productID)
        }
    }

    /// Find all USB devices matching a specific Vendor ID.
    public static func findDevices(vendorID: UInt16) -> [USBDeviceInfo] {
        findAllDevices().filter { $0.vendorID == vendorID }
    }

    /// Find a device by VID + PID. Returns the IOKit service for opening.
    public static func findDevice(vendorID: UInt16, productID: UInt16) -> USBDeviceInfo? {
        findAllDevices().first { $0.vendorID == vendorID && $0.productID == productID }
    }

    /// Find all connected USB host devices.
    public static func findAllDevices() -> [USBDeviceInfo] {
        guard let matching = IOServiceMatching("IOUSBHostDevice") else { return [] }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [USBDeviceInfo] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }

            let vid = registryInt(service: service, key: "idVendor")
            let pid = registryInt(service: service, key: "idProduct")
            let name = registryString(service: service, key: "USB Product Name") ?? "Unknown"

            devices.append(USBDeviceInfo(
                vendorID: UInt16(vid),
                productID: UInt16(pid),
                name: name,
                service: service
            ))
            // Note: caller must IOObjectRelease(service) if they use it
        }

        return devices
    }

    // MARK: - Private

    private static func registryInt(service: io_service_t, key: String) -> Int {
        let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return (ref?.takeRetainedValue() as? Int) ?? 0
    }

    private static func registryString(service: io_service_t, key: String) -> String? {
        let ref = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)
        return ref?.takeRetainedValue() as? String
    }
}
