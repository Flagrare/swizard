import XCTest
@testable import NetworkTransport

final class HTTPFileServerTests: XCTestCase {

    private var server: HTTPFileServer!
    private let testPort: UInt16 = 18080

    override func setUp() {
        super.setUp()
        server = HTTPFileServer(port: testPort)
    }

    override func tearDown() {
        server.stop()
        server = nil
        super.tearDown()
    }

    // MARK: - Full file serving

    func testServesFullFile() async throws {
        let content = Data(repeating: 0xAB, count: 256)
        let url = try createTempFile(name: "test_full.nsp", content: content)

        server.register(files: [url])
        try server.start()

        // Give server a moment to start
        try await Task.sleep(for: .seconds(0.2))

        let (data, response) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(testPort)/0")!
        )

        let httpResponse = response as! HTTPURLResponse
        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(data, content)
    }

    // MARK: - Range request

    func testServesPartialContent() async throws {
        var content = Data(repeating: 0x00, count: 100)
        content.append(Data(repeating: 0xFF, count: 50))
        content.append(Data(repeating: 0x00, count: 100))
        let url = try createTempFile(name: "test_range.nsp", content: content)

        server.register(files: [url])
        try server.start()
        try await Task.sleep(for: .seconds(0.2))

        var request = URLRequest(url: URL(string: "http://localhost:\(testPort)/0")!)
        request.setValue("bytes=100-149", forHTTPHeaderField: "Range")

        let (data, response) = try await URLSession.shared.data(for: request)

        let httpResponse = response as! HTTPURLResponse
        XCTAssertEqual(httpResponse.statusCode, 206)
        XCTAssertEqual(data.count, 50)
        XCTAssertEqual(data, Data(repeating: 0xFF, count: 50))
    }

    // MARK: - 404 for unknown file

    func testReturns404ForUnknownFile() async throws {
        server.register(files: [])
        try server.start()
        try await Task.sleep(for: .seconds(0.2))

        let (_, response) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(testPort)/99")!
        )

        let httpResponse = response as! HTTPURLResponse
        XCTAssertEqual(httpResponse.statusCode, 404)
    }

    // MARK: - Multiple files

    func testServesMultipleFiles() async throws {
        let content1 = Data(repeating: 0xAA, count: 100)
        let content2 = Data(repeating: 0xBB, count: 200)
        let url1 = try createTempFile(name: "game1.nsp", content: content1)
        let url2 = try createTempFile(name: "game2.xci", content: content2)

        server.register(files: [url1, url2])
        try server.start()
        try await Task.sleep(for: .seconds(0.2))

        let (data0, _) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(testPort)/0")!
        )
        let (data1, _) = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(testPort)/1")!
        )

        XCTAssertEqual(data0, content1)
        XCTAssertEqual(data1, content2)
    }

    // MARK: - File URL list

    func testFileURLListGeneration() {
        let url1 = URL(fileURLWithPath: "/tmp/game1.nsp")
        let url2 = URL(fileURLWithPath: "/tmp/game2.xci")

        server.register(files: [url1, url2])
        let list = server.fileURLList(host: "192.168.1.10")

        XCTAssertEqual(list, "http://192.168.1.10:\(testPort)/0\nhttp://192.168.1.10:\(testPort)/1")
    }

    // MARK: - Progress callback

    func testProgressCallbackFired() async throws {
        let content = Data(repeating: 0xCC, count: 500)
        let url = try createTempFile(name: "test_progress.nsp", content: content)

        let collector = ProgressCollector()
        server.register(files: [url])
        server.onProgress = { fileIndex, bytesSent, totalSize in
            collector.add(fileIndex: fileIndex, bytesSent: bytesSent, totalSize: totalSize)
        }
        try server.start()
        try await Task.sleep(for: .seconds(0.2))

        let _ = try await URLSession.shared.data(
            from: URL(string: "http://localhost:\(testPort)/0")!
        )

        XCTAssertFalse(collector.updates.isEmpty)
        XCTAssertEqual(collector.updates[0].fileIndex, 0)
        XCTAssertEqual(collector.updates[0].totalSize, 500)
    }

    // MARK: - Helpers

    private func createTempFile(name: String, content: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try content.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private final class ProgressCollector: @unchecked Sendable {
    struct Update { let fileIndex: Int; let bytesSent: UInt64; let totalSize: UInt64 }
    private(set) var updates: [Update] = []

    func add(fileIndex: Int, bytesSent: UInt64, totalSize: UInt64) {
        updates.append(Update(fileIndex: fileIndex, bytesSent: bytesSent, totalSize: totalSize))
    }
}
