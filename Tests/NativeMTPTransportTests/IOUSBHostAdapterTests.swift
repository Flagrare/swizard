import XCTest
@testable import NativeMTPTransport
import DBIProtocol

final class IOUSBHostAdapterTests: XCTestCase {

    // MARK: - Mock adapter behavior

    func testMockOpenRecordsVIDPID() async throws {
        let mock = MockUSBBulkTransfer()
        try await mock.open(vendorID: NintendoSwitchUSB.vendorID, productID: NintendoSwitchUSB.mtpProductID)

        XCTAssertTrue(mock.isOpen)
        XCTAssertEqual(mock.openedVendorID, NintendoSwitchUSB.vendorID)
        XCTAssertEqual(mock.openedProductID, NintendoSwitchUSB.mtpProductID)
    }

    func testMockCloseMarksNotOpen() async throws {
        let mock = MockUSBBulkTransfer()
        try await mock.open(vendorID: NintendoSwitchUSB.vendorID, productID: NintendoSwitchUSB.mtpProductID)
        await mock.close()

        XCTAssertFalse(mock.isOpen)
    }

    func testMockOpenFailureThrows() async {
        let mock = MockUSBBulkTransfer()
        mock.openShouldFail = true

        do {
            try await mock.open(vendorID: NintendoSwitchUSB.vendorID, productID: NintendoSwitchUSB.mtpProductID)
            XCTFail("Should have thrown")
        } catch let error as IOUSBHostError {
            XCTAssertEqual(error, .deviceNotFound)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testMockReadReturnsQueuedData() async throws {
        let mock = MockUSBBulkTransfer()
        let expected = Data([0xAA, 0xBB, 0xCC])
        mock.queueRead(expected)

        let result = try await mock.readBulk(maxLength: 100)
        XCTAssertEqual(result, expected)
    }

    func testMockReadThrowsWhenQueueEmpty() async {
        let mock = MockUSBBulkTransfer()

        do {
            _ = try await mock.readBulk(maxLength: 100)
            XCTFail("Should have thrown")
        } catch {
            // Expected
        }
    }

    func testMockWriteRecordsData() async throws {
        let mock = MockUSBBulkTransfer()
        let data = Data([0x01, 0x02, 0x03])

        try await mock.writeBulk(data)

        XCTAssertEqual(mock.writtenData.count, 1)
        XCTAssertEqual(mock.writtenData[0], data)
    }

    // MARK: - MTP container round-trip via mock

    func testWriteAndReadMTPContainerViaMock() async throws {
        let mock = MockUSBBulkTransfer()

        // Queue an OK response
        mock.queueResponse(code: 0x2001, transactionID: 1)

        // Write a command
        let command = MTPContainer(
            type: .command,
            code: MTPOperation.openSession.rawValue,
            transactionID: 1,
            payload: withUnsafeBytes(of: UInt32(1).littleEndian) { Data($0) }
        )
        try await mock.writeBulk(command.encoded())

        // Read the response
        let responseData = try await mock.readBulk(maxLength: 512)
        let response = try MTPContainer(from: responseData)

        XCTAssertEqual(response.type, .response)
        XCTAssertEqual(response.code, MTPResponseCode.ok.rawValue)
        XCTAssertEqual(response.transactionID, 1)

        // Verify command was written
        let written = try mock.writtenContainer(at: 0)
        XCTAssertEqual(written.type, .command)
        XCTAssertEqual(written.code, MTPOperation.openSession.rawValue)
    }

    // MARK: - Error type tests

    func testIOUSBHostErrorDescriptions() {
        XCTAssertNotNil(IOUSBHostError.deviceNotFound.errorDescription)
        XCTAssertNotNil(IOUSBHostError.seizeRejected.errorDescription)
        XCTAssertTrue(IOUSBHostError.seizeRejected.errorDescription!.contains("replugging"))
    }
}
