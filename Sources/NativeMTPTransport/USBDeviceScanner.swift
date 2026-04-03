import Foundation
import IOKit
import IOKit.usb

/// Scans all connected USB devices. Used as fallback when known PIDs don't match.
public enum USBDeviceScanner {
    public struct USBDeviceInfo: Sendable, CustomStringConvertible {
        public let vendorID: UInt16
        public let productID: UInt16
        public let name: String

        public var description: String {
            String(format: "%@ (VID: 0x%04X, PID: 0x%04X)", name, vendorID, productID)
        }
    }

    /// Find all USB devices matching a specific Vendor ID.
    public static func findDevices(vendorID: UInt16) -> [USBDeviceInfo] {
        let matching = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        matching["idVendor"] = vendorID

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        var devices: [USBDeviceInfo] = []
        while true {
            let service = IOIteratorNext(iterator)
            guard service != 0 else { break }
            defer { IOObjectRelease(service) }

            let pid = ioRegistryValue(service: service, key: "idProduct") as? Int ?? 0
            let name = ioRegistryValue(service: service, key: "USB Product Name") as? String ?? "Unknown"

            devices.append(USBDeviceInfo(
                vendorID: vendorID,
                productID: UInt16(pid),
                name: name
            ))
        }

        return devices
    }

    /// Find all USB devices (any vendor). Useful for debugging.
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
            defer { IOObjectRelease(service) }

            let vid = ioRegistryValue(service: service, key: "idVendor") as? Int ?? 0
            let pid = ioRegistryValue(service: service, key: "idProduct") as? Int ?? 0
            let name = ioRegistryValue(service: service, key: "USB Product Name") as? String ?? "Unknown"

            devices.append(USBDeviceInfo(
                vendorID: UInt16(vid),
                productID: UInt16(pid),
                name: name
            ))
        }

        return devices
    }

    private static func ioRegistryValue(service: io_service_t, key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
