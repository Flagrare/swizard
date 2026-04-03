import XCTest
@testable import Installer

final class TransferProgressTests: XCTestCase {

    func testRegisterAddsFileWithZeroProgress() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)

        XCTAssertEqual(progress.files.count, 1)
        XCTAssertEqual(progress.files[0].name, "game.nsp")
        XCTAssertEqual(progress.files[0].totalBytes, 1000)
        XCTAssertEqual(progress.files[0].transferredBytes, 0)
        XCTAssertEqual(progress.files[0].fraction, 0)
        XCTAssertFalse(progress.files[0].isComplete)
    }

    func testUpdateProgressSetsTransferredBytes() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)

        progress.updateProgress(fileName: "game.nsp", transferredBytes: 500)

        XCTAssertEqual(progress.files[0].transferredBytes, 500)
        XCTAssertEqual(progress.files[0].fraction, 0.5)
        XCTAssertEqual(progress.currentFileName, "game.nsp")
    }

    func testFileMarkedCompleteWhenFullyTransferred() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)

        progress.updateProgress(fileName: "game.nsp", transferredBytes: 1000)

        XCTAssertTrue(progress.files[0].isComplete)
        XCTAssertEqual(progress.files[0].fraction, 1.0)
    }

    func testOverallFractionAcrossMultipleFiles() {
        let progress = TransferProgress()
        progress.register(name: "game1.nsp", totalBytes: 1000)
        progress.register(name: "game2.nsp", totalBytes: 1000)

        progress.updateProgress(fileName: "game1.nsp", transferredBytes: 1000) // 100%
        progress.updateProgress(fileName: "game2.nsp", transferredBytes: 500)  // 50%

        // Overall: 1500 of 2000 = 75%
        XCTAssertEqual(progress.overallFraction, 0.75)
    }

    func testOverallFractionIsZeroWithNoFiles() {
        let progress = TransferProgress()
        XCTAssertEqual(progress.overallFraction, 0)
    }

    func testClearRemovesAllFiles() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)
        progress.updateProgress(fileName: "game.nsp", transferredBytes: 500)

        progress.clear()

        XCTAssertTrue(progress.files.isEmpty)
        XCTAssertNil(progress.currentFileName)
    }

    func testUpdateProgressIgnoresUnknownFileName() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)

        progress.updateProgress(fileName: "unknown.nsp", transferredBytes: 999)

        // Should not crash, and game.nsp should be unaffected
        XCTAssertEqual(progress.files[0].transferredBytes, 0)
    }

    func testZeroTotalBytesProducesZeroFraction() {
        let progress = TransferProgress()
        progress.register(name: "empty.nsp", totalBytes: 0)

        XCTAssertEqual(progress.files[0].fraction, 0)
    }

    func testApplyChunkAddsBytesWithoutUsingAbsoluteOffset() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)

        progress.applyChunk(fileName: "game.nsp", bytesInChunk: 100)
        progress.applyChunk(fileName: "game.nsp", bytesInChunk: 100)

        XCTAssertEqual(progress.files[0].transferredBytes, 200)
        XCTAssertEqual(progress.files[0].fraction, 0.2)
    }

    func testApplyChunkCapsProgressAtTotalBytes() {
        let progress = TransferProgress()
        progress.register(name: "game.nsp", totalBytes: 1000)

        progress.applyChunk(fileName: "game.nsp", bytesInChunk: 900)
        progress.applyChunk(fileName: "game.nsp", bytesInChunk: 500)

        XCTAssertEqual(progress.files[0].transferredBytes, 1000)
        XCTAssertEqual(progress.files[0].fraction, 1.0)
        XCTAssertTrue(progress.files[0].isComplete)
    }
}
