import Foundation

/// Tracks per-file and overall transfer progress.
@Observable
public final class TransferProgress: @unchecked Sendable {
    public struct FileProgress: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let totalBytes: UInt64
        public var transferredBytes: UInt64 = 0

        public var fraction: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(transferredBytes) / Double(totalBytes)
        }

        public var isComplete: Bool { transferredBytes >= totalBytes }
    }

    public var files: [FileProgress] = []
    public var currentFileName: String?

    public var overallFraction: Double {
        let totalBytes = files.reduce(0) { $0 + $1.totalBytes }
        let transferred = files.reduce(0) { $0 + $1.transferredBytes }
        guard totalBytes > 0 else { return 0 }
        return Double(transferred) / Double(totalBytes)
    }

    public init() {}

    public func register(name: String, totalBytes: UInt64) {
        files.append(FileProgress(id: name, name: name, totalBytes: totalBytes))
    }

    public func updateProgress(fileName: String, transferredBytes: UInt64) {
        guard let index = files.firstIndex(where: { $0.name == fileName }) else { return }
        files[index].transferredBytes = transferredBytes
        currentFileName = fileName
    }

    public func clear() {
        files.removeAll()
        currentFileName = nil
    }
}
