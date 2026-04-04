import Foundation

/// Adapter: uploads files to DBI's FTP server via curl.
/// curl handles PASV mode, chunking, and FTP protocol internally.
public final class FTPUploadClient: FTPUploadClientProtocol, @unchecked Sendable {

    public init() {}

    /// Build curl command-line arguments for FTP upload.
    public func buildCurlArguments(file: URL, connection: FTPConnectionInfo) -> [String] {
        let remoteName = file.lastPathComponent
        let ftpURL = connection.uploadURL(for: remoteName)

        return [
            "-T", file.path,
            ftpURL,
            "--user", "\(DBIFTPConstants.username):\(DBIFTPConstants.password)",
            "--disable-epsv",   // DBI doesn't support EPSV
            "--progress-bar",   // Enable progress output for parsing
            "--ftp-pasv",       // Force PASV mode
        ]
    }

    public func upload(
        file: URL,
        to connection: FTPConnectionInfo,
        onProgress: @escaping @Sendable (Double) -> Void,
        onLog: @escaping @Sendable (String) -> Void
    ) async throws {
        let args = buildCurlArguments(file: file, connection: connection)
        let ftpURL = connection.uploadURL(for: file.lastPathComponent)
        onLog("Uploading \(file.lastPathComponent) to \(connection.displayString)...")
        onLog("curl URL: \(ftpURL)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
        process.arguments = args

        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe() // discard stdout

        try process.run()

        // Read stderr for progress + error messages
        let handle = stderrPipe.fileHandleForReading
        var allStderr = ""

        while process.isRunning {
            let data = handle.availableData
            guard !data.isEmpty else {
                try await Task.sleep(for: .milliseconds(100))
                continue
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            allStderr += text
            for line in text.components(separatedBy: "\r") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let progress = CurlProgressParser.parse(trimmed) {
                    onProgress(progress.percentage)
                } else if !trimmed.isEmpty && trimmed.contains("curl:") {
                    onLog("curl: \(trimmed)")
                }
            }
        }

        // Read remaining
        let remaining = handle.readDataToEndOfFile()
        if let text = String(data: remaining, encoding: .utf8) {
            allStderr += text
            for line in text.components(separatedBy: "\r") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if let progress = CurlProgressParser.parse(trimmed) {
                    onProgress(progress.percentage)
                }
            }
        }

        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // Log the full stderr for debugging
            let stderrSummary = allStderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if !stderrSummary.isEmpty {
                onLog("curl stderr: \(stderrSummary.prefix(500))")
            }
            throw FTPUploadError.transferFailed("curl exited with code \(process.terminationStatus)")
        }

        onLog("\(file.lastPathComponent) uploaded successfully")
    }
}
