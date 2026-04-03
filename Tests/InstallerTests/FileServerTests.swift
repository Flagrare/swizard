import XCTest
@testable import Installer

final class FileServerTests: XCTestCase {

    func testFileListReturnsSortedNames() throws {
        let server = FileServer()
        let (url1, url2) = try createTempFiles(["zebra.nsp": 10, "alpha.xci": 20])

        server.register(files: [url1, url2])
        XCTAssertEqual(server.fileList(), "alpha.xci\nzebra.nsp\n")
    }

    func testReadRangeReturnsCorrectBytes() throws {
        let content = Data([0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77])
        let url = try createTempFile(name: "test.nsp", content: content)

        let server = FileServer()
        server.register(files: [url])

        // Read 3 bytes starting at offset 2
        let data = try server.readRange(fileName: "test.nsp", offset: 2, size: 3)
        XCTAssertEqual(data, Data([0x22, 0x33, 0x44]))
    }

    func testReadRangeAtOffset() throws {
        var content = Data(repeating: 0x00, count: 100)
        content.append(Data(repeating: 0xFF, count: 50))
        let url = try createTempFile(name: "offset.nsp", content: content)

        let server = FileServer()
        server.register(files: [url])

        let data = try server.readRange(fileName: "offset.nsp", offset: 100, size: 50)
        XCTAssertEqual(data, Data(repeating: 0xFF, count: 50))
    }

    func testReadRangeThrowsForUnknownFile() throws {
        let server = FileServer()

        XCTAssertThrowsError(try server.readRange(fileName: "missing.nsp", offset: 0, size: 10))
    }

    func testEmptyFileList() {
        let server = FileServer()
        XCTAssertEqual(server.fileList(), "")
        XCTAssertEqual(server.fileCount, 0)
    }

    // MARK: - Helpers

    private func createTempFile(name: String, content: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try content.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func createTempFiles(_ files: [String: Int]) throws -> (URL, URL) {
        let sorted = files.sorted { $0.key < $1.key }
        let url1 = try createTempFile(name: sorted[0].key, content: Data(repeating: 0, count: sorted[0].value))
        let url2 = try createTempFile(name: sorted[1].key, content: Data(repeating: 0, count: sorted[1].value))
        return (url1, url2)
    }
}
