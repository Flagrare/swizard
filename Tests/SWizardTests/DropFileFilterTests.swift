import XCTest
@testable import SWizard

final class DropFileFilterTests: XCTestCase {

    func testResolveSupportedURLAcceptsSupportedExtension() {
        let url = URL(fileURLWithPath: "/tmp/game.nsp")

        let resolved = DropFileFilter.resolveSupportedURL(fromFileURLData: url.dataRepresentation)

        XCTAssertEqual(resolved, url)
    }

    func testResolveSupportedURLAcceptsUppercaseExtension() {
        let url = URL(fileURLWithPath: "/tmp/game.XCI")

        let resolved = DropFileFilter.resolveSupportedURL(fromFileURLData: url.dataRepresentation)

        XCTAssertEqual(resolved, url)
    }

    func testResolveSupportedURLRejectsUnsupportedExtension() {
        let url = URL(fileURLWithPath: "/tmp/readme.txt")

        let resolved = DropFileFilter.resolveSupportedURL(fromFileURLData: url.dataRepresentation)

        XCTAssertNil(resolved)
    }

    func testSupportedExtensionsMatchGameFormats() {
        // File picker should filter to exactly these extensions
        XCTAssertTrue(DropFileFilter.supportedExtensions.contains("nsp"))
        XCTAssertTrue(DropFileFilter.supportedExtensions.contains("nsz"))
        XCTAssertTrue(DropFileFilter.supportedExtensions.contains("xci"))
        XCTAssertTrue(DropFileFilter.supportedExtensions.contains("xcz"))
        XCTAssertEqual(DropFileFilter.supportedExtensions.count, 4)
    }

    func testResolveSupportedURLRejectsInvalidData() {
        let resolved = DropFileFilter.resolveSupportedURL(fromFileURLData: Data([0x01, 0x02, 0x03]))

        XCTAssertNil(resolved)
    }
}
