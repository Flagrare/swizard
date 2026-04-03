import Foundation
import Network

/// Lightweight HTTP file server using Network.framework (NWListener).
/// Serves registered files at /0, /1, /2... with Range request support.
public final class HTTPFileServer: @unchecked Sendable {
    private let port: UInt16
    private var listener: NWListener?
    private var files: [(url: URL, size: UInt64)] = []
    private let queue = DispatchQueue(label: "com.swizard.httpserver")
    public var onProgress: (@Sendable (_ fileIndex: Int, _ bytesSent: UInt64, _ totalSize: UInt64) -> Void)?

    public init(port: UInt16 = 5000) {
        self.port = port
    }

    public func register(files urls: [URL]) {
        self.files = urls.map { url in
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
            return (url: url, size: size)
        }
    }

    /// Returns the newline-separated URL list the Switch needs to download files.
    public func fileURLList(host: String) -> String {
        files.indices.map { "http://\(host):\(port)/\($0)" }.joined(separator: "\n")
    }

    public func start() throws {
        let params = NWParameters.tcp
        let nwPort = NWEndpoint.Port(rawValue: port)!
        listener = try NWListener(using: params, on: nwPort)

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handleConnection(connection)
        }

        listener?.stateUpdateHandler = { state in
            if case .failed(let error) = state {
                print("HTTP server failed: \(error)")
            }
        }

        listener?.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection Handling

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: queue)
        receiveRequest(on: connection)
    }

    private func receiveRequest(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, error in
            guard let self, let data, error == nil else {
                connection.cancel()
                return
            }

            guard let rawRequest = String(data: data, encoding: .utf8),
                  let request = try? HTTPRequest.parse(rawRequest) else {
                self.sendResponse(HTTPResponse.notFound(), on: connection)
                return
            }

            self.handleRequest(request, on: connection)
        }
    }

    private func handleRequest(_ request: HTTPRequest, on connection: NWConnection) {
        guard let fileIndex = HTTPRequest.fileIndex(from: request.path),
              fileIndex >= 0 && fileIndex < files.count else {
            sendResponse(HTTPResponse.notFound(), on: connection)
            return
        }

        let file = files[fileIndex]

        if request.method == "HEAD" {
            let response = HTTPResponse.ok(data: Data(), totalSize: file.size)
            sendResponse(response, on: connection)
            return
        }

        // Read the requested range
        do {
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { handle.closeFile() }

            let response: HTTPResponse
            if let range = request.range {
                let end = range.end ?? (file.size - 1)
                let length = end - range.start + 1
                handle.seek(toFileOffset: range.start)
                let data = handle.readData(ofLength: Int(length))

                response = HTTPResponse.partialContent(
                    data: data,
                    rangeStart: range.start,
                    rangeEnd: range.start + UInt64(data.count) - 1,
                    totalSize: file.size
                )

                onProgress?(fileIndex, range.start + UInt64(data.count), file.size)
            } else {
                let data = handle.readData(ofLength: Int(file.size))
                response = HTTPResponse.ok(data: data, totalSize: file.size)
                onProgress?(fileIndex, file.size, file.size)
            }

            sendResponse(response, on: connection)
        } catch {
            sendResponse(HTTPResponse.notFound(), on: connection)
        }
    }

    private func sendResponse(_ response: HTTPResponse, on connection: NWConnection) {
        connection.send(content: response.serialized(), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
