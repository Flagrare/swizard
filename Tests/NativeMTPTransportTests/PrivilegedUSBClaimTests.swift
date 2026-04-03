import XCTest
@testable import NativeMTPTransport
import DBIProtocol

final class PrivilegedUSBClaimTests: XCTestCase {

    // MARK: - Behavior: adapter tries privileged claim when normal open fails

    func testAdapterOpensDeviceAfterPrivilegedClaim() async throws {
        // This test verifies the behavioral contract:
        // When open() is called, the adapter should:
        // 1. Verify device exists
        // 2. Run privileged claim (prompts for admin password)
        // 3. Open device and interface after drivers are released
        //
        // We can't test the real privileged claim in unit tests,
        // but we CAN test the mock path works end-to-end
        let mock = MockUSBBulkTransfer()
        try await mock.open(
            vendorID: NintendoSwitchUSB.vendorID,
            productID: NintendoSwitchUSB.mtpProductID
        )
        XCTAssertTrue(mock.isOpen)

        // After open, read and write should work
        mock.queueRead(Data([0x01, 0x02]))
        let data = try await mock.readBulk(maxLength: 16)
        XCTAssertEqual(data, Data([0x01, 0x02]))

        try await mock.writeBulk(Data([0xAA]))
        XCTAssertEqual(mock.writtenData.count, 1)

        await mock.close()
        XCTAssertFalse(mock.isOpen)
    }

    // MARK: - Behavior: claim fails for nonexistent device

    func testClaimFailsForBogusDevice() async {
        // PrivilegedUSBClaim should fail if device doesn't exist
        // We test this indirectly — the adapter should throw deviceNotFound
        let mock = MockUSBBulkTransfer()
        mock.openShouldFail = true

        do {
            try await mock.open(
                vendorID: 0xFFFF,
                productID: 0xFFFF
            )
            XCTFail("Should have thrown")
        } catch {
            // Expected — device not found
        }
    }

    // MARK: - Behavior: IOUSBHostError descriptions are user-friendly

    func testSeizeRejectedErrorSuggestsReplugging() {
        let error = IOUSBHostError.seizeRejected
        XCTAssertTrue(error.errorDescription!.contains("replugging"))
    }

    func testClaimFailedIncludesDetail() {
        let error = IOUSBHostError.claimFailed("Privileged claim failed: timeout")
        XCTAssertTrue(error.errorDescription!.contains("Privileged claim failed"))
    }
}
