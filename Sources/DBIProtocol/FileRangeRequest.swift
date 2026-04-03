import Foundation

/// Parsed FILE_RANGE command payload (value object).
/// Layout: rangeSize(4B LE) + rangeOffset(8B LE) + nameLen(4B LE) + name(variable UTF-8)
public struct FileRangeRequest: Equatable, Sendable {
    public let rangeSize: UInt32
    public let rangeOffset: UInt64
    public let fileName: String

    static let minimumPayloadSize = 16 // 4 + 8 + 4

    public init(from data: Data) throws {
        guard data.count >= Self.minimumPayloadSize else {
            throw DBIError.invalidPayloadSize(data.count)
        }

        self.rangeSize = data.loadLittleEndianUInt32(at: 0)
        self.rangeOffset = data.loadLittleEndianUInt64(at: 4)

        let nameLength = data.loadLittleEndianUInt32(at: 12)
        let nameStart = data.startIndex + 16
        let nameEnd = nameStart + Int(nameLength)

        guard nameEnd <= data.endIndex else {
            throw DBIError.invalidPayloadSize(data.count)
        }

        let nameData = data[nameStart..<nameEnd]
        guard let name = String(data: nameData, encoding: .utf8) else {
            throw DBIError.fileNameDecodingFailed
        }

        self.fileName = name
    }
}
