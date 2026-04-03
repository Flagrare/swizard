import Foundation

/// Facade: manages the HTTP file server lifecycle for network installation.
/// The Switch's DBI HTTP client connects to this server to download files.
public final class NetworkInstallServer: @unchecked Sendable {
    private let server: HTTPFileServer
    private let port: UInt16

    public init(port: UInt16 = 5000) {
        self.port = port
        self.server = HTTPFileServer(port: port)
    }

    /// Register files to serve and start the HTTP server.
    public func start(
        files: [URL],
        onProgress: @escaping @Sendable (_ fileIndex: Int, _ bytesSent: UInt64, _ totalSize: UInt64) -> Void
    ) throws -> String {
        server.register(files: files)
        server.onProgress = onProgress

        let host = Self.localIPAddress() ?? "localhost"
        try server.start()

        return server.fileURLList(host: host)
    }

    /// Stop the HTTP server.
    public func stop() {
        server.stop()
    }

    /// Get the local IP address for display to the user.
    public static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?

        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            let family = interface.ifa_addr.pointee.sa_family

            guard family == UInt8(AF_INET) else { continue }

            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                interface.ifa_addr,
                socklen_t(interface.ifa_addr.pointee.sa_len),
                &hostname,
                socklen_t(hostname.count),
                nil, 0,
                NI_NUMERICHOST
            )

            if result == 0 {
                address = String(cString: hostname)
                break
            }
        }

        return address
    }
}
