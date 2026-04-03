import Foundation

/// HTTP response builder (Value Object).
public struct HTTPResponse: Sendable {
    public let statusLine: String
    public let headers: [String]
    public let body: Data

    /// Serialize to raw HTTP response bytes.
    public func serialized() -> Data {
        var result = Data()
        result.append(Data((statusLine + "\r\n").utf8))
        for header in headers {
            result.append(Data((header + "\r\n").utf8))
        }
        result.append(Data("\r\n".utf8))
        result.append(body)
        return result
    }

    /// 206 Partial Content — serves a byte range.
    public static func partialContent(
        data: Data,
        rangeStart: UInt64,
        rangeEnd: UInt64,
        totalSize: UInt64
    ) -> HTTPResponse {
        HTTPResponse(
            statusLine: "HTTP/1.1 206 Partial Content",
            headers: [
                "Content-Type: application/octet-stream",
                "Content-Length: \(data.count)",
                "Content-Range: bytes \(rangeStart)-\(rangeEnd)/\(totalSize)",
                "Accept-Ranges: bytes",
            ],
            body: data
        )
    }

    /// 200 OK — serves the full file.
    public static func ok(data: Data, totalSize: UInt64) -> HTTPResponse {
        HTTPResponse(
            statusLine: "HTTP/1.1 200 OK",
            headers: [
                "Content-Type: application/octet-stream",
                "Content-Length: \(data.count)",
                "Accept-Ranges: bytes",
            ],
            body: data
        )
    }

    /// 404 Not Found.
    public static func notFound() -> HTTPResponse {
        HTTPResponse(
            statusLine: "HTTP/1.1 404 Not Found",
            headers: ["Content-Length: 0"],
            body: Data()
        )
    }
}
