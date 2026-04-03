import Foundation
import DBIProtocol

/// Serves file chunks to DBI during installation.
/// Maps file names to local URLs and reads byte ranges on demand.
public final class FileServer: FileServing, @unchecked Sendable {
    private var files: [String: URL] = [:]

    public init() {}

    public func register(files urls: [URL]) {
        for url in urls {
            files[url.lastPathComponent] = url
        }
    }

    public func fileList() -> String {
        let names = files.keys.sorted()
        guard !names.isEmpty else { return "" }
        return names.map { $0 + "\n" }.joined()
    }

    public func readRange(fileName: String, offset: UInt64, size: UInt32) throws -> Data {
        guard let url = files[fileName] else {
            throw InstallError.fileNotFound(fileName)
        }

        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }

            handle.seek(toFileOffset: offset)
            let data = handle.readData(ofLength: Int(size))
            return data
        } catch {
            throw InstallError.fileReadFailed(fileName, error)
        }
    }

    public var fileCount: Int { files.count }

    public func totalSize() throws -> UInt64 {
        try files.values.reduce(0) { total, url in
            let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
            let size = attrs[.size] as? UInt64 ?? 0
            return total + size
        }
    }
}
