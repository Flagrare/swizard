import XCTest
@testable import Installer

final class FileServerTests: XCTestCase {
    func testInstallErrorDescriptions() {
        let error = InstallError.cancelled
        XCTAssertEqual(error.errorDescription, "Installation cancelled")
    }
}
