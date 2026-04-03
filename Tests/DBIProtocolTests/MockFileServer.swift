import Foundation
@testable import DBIProtocol

/// Test double for file serving.
/// Returns scripted file lists and byte ranges.
final class MockFileServer: FileServing, @unchecked Sendable {
    var files: [String: Data] = [:]

    func register(name: String, content: Data) {
        files[name] = content
    }

    func fileList() -> String {
        let names = files.keys.sorted()
        guard !names.isEmpty else { return "" }
        return names.map { $0 + "\n" }.joined()
    }

    func readRange(fileName: String, offset: UInt64, size: UInt32) throws -> Data {
        guard let content = files[fileName] else {
            throw MockFileServerError.fileNotFound(fileName)
        }
        let start = Int(offset)
        let end = min(start + Int(size), content.count)
        return content[start..<end]
    }
}

enum MockFileServerError: Error {
    case fileNotFound(String)
}
