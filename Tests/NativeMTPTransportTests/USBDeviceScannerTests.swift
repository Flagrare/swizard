import XCTest
@testable import NativeMTPTransport
import DBIProtocol

final class USBDeviceScannerTests: XCTestCase {

    func testFindAllDevicesReturnsNonEmpty() {
        // On any Mac, there's at least an internal USB hub
        let devices = USBDeviceScanner.findAllDevices()
        XCTAssertFalse(devices.isEmpty, "Should find at least one USB device on any Mac")
    }

    func testDeviceInfoHasValidVendorID() {
        let devices = USBDeviceScanner.findAllDevices()
        for device in devices {
            XCTAssertNotEqual(device.vendorID, 0, "VID should not be 0 for \(device.name)")
        }
    }

    func testFindDevicesFiltersByVendorID() {
        let allDevices = USBDeviceScanner.findAllDevices()
        guard let first = allDevices.first else { return }

        let filtered = USBDeviceScanner.findDevices(vendorID: first.vendorID)
        XCTAssertTrue(filtered.allSatisfy { $0.vendorID == first.vendorID })
    }

    func testFindDevicesReturnsEmptyForBogusVendor() {
        let devices = USBDeviceScanner.findDevices(vendorID: 0xFFFF)
        XCTAssertTrue(devices.isEmpty)
    }

    func testFindDeviceByVIDPIDReturnsNilForBogus() {
        let device = USBDeviceScanner.findDevice(vendorID: 0xFFFF, productID: 0xFFFF)
        XCTAssertNil(device)
    }

    func testDeviceInfoDescription() {
        let info = USBDeviceScanner.USBDeviceInfo(
            vendorID: 0x057E,
            productID: 0x201D,
            name: "DBI",
            service: 0
        )
        XCTAssertTrue(info.description.contains("DBI"))
        XCTAssertTrue(info.description.contains("057E"))
        XCTAssertTrue(info.description.contains("201D"))
    }
}
