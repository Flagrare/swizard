import Foundation
import DBIProtocol

/// Runs a full MTP installation session inside a privileged (root) process.
/// The privileged process holds DeviceCapture for the entire MTP conversation,
/// avoiding the composite driver re-claim issue.
///
/// Communication via stdout lines:
///   LOG:message          — informational log
///   PROGRESS:name:sent:total — file transfer progress
///   OK                   — session completed successfully
///   ERROR:message        — session failed
public final class PrivilegedMTPSession: @unchecked Sendable {

    public struct FileToInstall: Sendable {
        public let path: String
        public let name: String
        public let size: UInt64

        public init(path: String, name: String, size: UInt64) {
            self.path = path
            self.name = name
            self.size = size
        }
    }

    public typealias ProgressHandler = @Sendable (String, UInt64, UInt64) -> Void
    public typealias LogHandler = @Sendable (String) -> Void

    private let vendorID: UInt16
    private let productID: UInt16

    public init(vendorID: UInt16 = NintendoSwitchUSB.vendorID,
                productID: UInt16 = NintendoSwitchUSB.mtpProductID) {
        self.vendorID = vendorID
        self.productID = productID
    }

    /// Run the MTP install session with admin privileges.
    /// Prompts the user for their admin password once.
    public func install(
        files: [FileToInstall],
        onProgress: @escaping ProgressHandler,
        onLog: @escaping LogHandler
    ) async throws {
        let script = Self.buildScript(vendorID: vendorID, productID: productID, files: files)

        onLog("Requesting admin privileges...")

        // Write script to temp file to avoid shell escaping issues
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("swizard_mtp_\(UUID().uuidString).swift")
        try script.write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let shellCmd = "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift \\\"" + tempFile.path + "\\\" 2>&1"
        let osascript = "do shell script \"\(shellCmd)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", osascript]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        // Stream output line by line
        let handle = pipe.fileHandleForReading
        var resultOK = false

        while process.isRunning || handle.availableData.count > 0 {
            let data = handle.availableData
            guard !data.isEmpty else {
                if !process.isRunning { break }
                try await Task.sleep(for: .milliseconds(100))
                continue
            }

            let text = String(data: data, encoding: .utf8) ?? ""
            for line in text.components(separatedBy: "\n") where !line.isEmpty {
                let output = PrivilegedMTPOutput.parse(line)
                switch output {
                case .progress(let name, let sent, let total):
                    onProgress(name, sent, total)
                case .success:
                    resultOK = true
                case .error(let msg):
                    throw IOUSBHostError.claimFailed(msg)
                case .log(let msg):
                    onLog(msg)
                }
            }
        }

        process.waitUntilExit()

        guard resultOK || process.terminationStatus == 0 else {
            throw IOUSBHostError.claimFailed("Privileged MTP session exited with code \(process.terminationStatus)")
        }
    }

    // MARK: - Script Generation

    /// Builds the Swift script that runs as root with DeviceCapture.
    /// The script does: find device → DeviceCapture → configure → open interface →
    /// MTP OpenSession → for each file: SendObjectInfo + SendObject → CloseSession
    public static func buildScript(
        vendorID: UInt16,
        productID: UInt16,
        files: [FileToInstall]
    ) -> String {
        let fileEntries = files.map { file in
            "FileEntry(path: \"\(file.path)\", name: \"\(file.name)\", size: \(file.size))"
        }.joined(separator: ",\n    ")

        return """
        import Foundation
        import IOKit
        import IOKit.usb
        import IOUSBHost

        let vid = \(vendorID)
        let pid = \(productID)

        struct FileEntry { let path: String; let name: String; let size: UInt64 }
        let files: [FileEntry] = [\(fileEntries.isEmpty ? "" : "\n    \(fileEntries)\n")]

        func findDevice() -> io_service_t? {
            guard let m = IOServiceMatching("IOUSBHostDevice") else { return nil }
            var it: io_iterator_t = 0
            guard IOServiceGetMatchingServices(0, m, &it) == KERN_SUCCESS else { return nil }
            defer { IOObjectRelease(it) }
            while true {
                let s = IOIteratorNext(it)
                guard s != 0 else { return nil }
                let v = IORegistryEntryCreateCFProperty(s, "idVendor" as CFString, nil, 0)?.takeRetainedValue() as? Int ?? 0
                let p = IORegistryEntryCreateCFProperty(s, "idProduct" as CFString, nil, 0)?.takeRetainedValue() as? Int ?? 0
                if v == vid && p == pid { return s }
                IOObjectRelease(s)
            }
        }

        guard let svc = findDevice() else { print("ERROR:Device not found"); exit(1) }
        print("LOG:Device found")

        do {
            let device = try IOUSBHostDevice(__ioService: svc, options: .deviceCapture, queue: .main, interestHandler: nil)
            print("LOG:DeviceCapture acquired")

            try device.__configure(withValue: 1, matchInterfaces: false)
            Thread.sleep(forTimeInterval: 0.5)
            print("LOG:Device configured")

            // Find interface child
            var ci: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(svc, kIOServicePlane, &ci) == KERN_SUCCESS else {
                print("ERROR:Cannot enumerate children"); exit(1)
            }
            var ifaceSvc: io_service_t = 0
            while true {
                let c = IOIteratorNext(ci)
                guard c != 0 else { break }
                var cn = [CChar](repeating: 0, count: 128)
                IOObjectGetClass(c, &cn)
                if String(cString: cn).contains("Interface") { ifaceSvc = c; break }
                IOObjectRelease(c)
            }
            IOObjectRelease(ci)
            guard ifaceSvc != 0 else { print("ERROR:No interface found"); exit(1) }

            let iface = try IOUSBHostInterface(__ioService: ifaceSvc, options: [], queue: .main, interestHandler: nil)
            print("LOG:Interface claimed")

            // Find bulk endpoints
            let configDesc = iface.configurationDescriptor
            let ifaceDesc = iface.interfaceDescriptor
            var inPipe: IOUSBHostPipe?
            var outPipe: IOUSBHostPipe?
            var epH: UnsafePointer<IOUSBDescriptorHeader>? = nil
            var ep = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, epH)
            while let e = ep {
                let addr = e.pointee.bEndpointAddress
                let tt = e.pointee.bmAttributes & 0x03
                if tt == 2 {
                    if addr & 0x80 != 0 && inPipe == nil { inPipe = try? iface.copyPipe(withAddress: Int(addr)) }
                    else if addr & 0x80 == 0 && outPipe == nil { outPipe = try? iface.copyPipe(withAddress: Int(addr)) }
                }
                epH = UnsafeRawPointer(e).assumingMemoryBound(to: IOUSBDescriptorHeader.self)
                ep = IOUSBGetNextEndpointDescriptor(configDesc, ifaceDesc, epH)
            }
            guard let inP = inPipe, let outP = outPipe else { print("ERROR:Endpoints not found"); exit(1) }
            print("LOG:Bulk endpoints ready")

            // MTP helpers
            var txID: UInt32 = 0
            func nextTx() -> UInt32 { txID += 1; return txID }

            func writeContainer(_ data: Data) throws {
                let md = NSMutableData(data: data)
                var bw: Int = 0
                try outP.__sendIORequest(with: md, bytesTransferred: &bw, completionTimeout: 10.0)
            }

            func readContainer() throws -> Data {
                let buf = NSMutableData(length: 16384)!
                var br: Int = 0
                try inP.__sendIORequest(with: buf, bytesTransferred: &br, completionTimeout: 10.0)
                return Data(buf.prefix(br))
            }

            func buildCmd(code: UInt16, tx: UInt32, params: [UInt32] = []) -> Data {
                var payload = Data()
                for p in params {
                    withUnsafeBytes(of: p.littleEndian) { payload.append(contentsOf: $0) }
                }
                let len = UInt32(12 + payload.count)
                var d = Data()
                withUnsafeBytes(of: len.littleEndian) { d.append(contentsOf: $0) }
                withUnsafeBytes(of: UInt16(1).littleEndian) { d.append(contentsOf: $0) } // Command
                withUnsafeBytes(of: code.littleEndian) { d.append(contentsOf: $0) }
                withUnsafeBytes(of: tx.littleEndian) { d.append(contentsOf: $0) }
                d.append(payload)
                return d
            }

            // MTP OpenSession
            let sessionTx = nextTx()
            try writeContainer(buildCmd(code: 0x1002, tx: sessionTx, params: [1]))
            let _ = try readContainer()
            print("LOG:MTP session opened")

            // MTP GetStorageIDs
            let storageTx = nextTx()
            try writeContainer(buildCmd(code: 0x1004, tx: storageTx))
            let storageData = try readContainer() // Data phase
            let storageResp = try readContainer() // Response phase
            print("LOG:Got storage IDs")

            // Parse storage IDs from data container
            var storageID: UInt32 = 0
            if storageData.count >= 16 {
                let payload = storageData.dropFirst(12) // skip container header
                if payload.count >= 8 {
                    // First 4 bytes = array count, next 4 bytes = first storage ID
                    var sid: UInt32 = 0
                    withUnsafeMutableBytes(of: &sid) { payload.dropFirst(4).copyBytes(to: $0) }
                    storageID = UInt32(littleEndian: sid)
                }
            }
            print("LOG:Using storage ID \\(storageID)")

            // MTP GetObjectHandles to find install folder
            let handlesTx = nextTx()
            try writeContainer(buildCmd(code: 0x1007, tx: handlesTx, params: [storageID, 0, 0xFFFFFFFF]))
            let handlesData = try readContainer()
            let _ = try readContainer() // response
            print("LOG:Got object handles")

            // For each file: SendObjectInfo + SendObject
            for file in files {
                print("LOG:Installing \\(file.name) (\\(file.size) bytes)")

                // SendObjectInfo
                let infoTx = nextTx()
                try writeContainer(buildCmd(code: 0x100C, tx: infoTx, params: [storageID, 0xFFFFFFFF]))

                // Build ObjectInfo dataset
                var objInfo = Data()
                withUnsafeBytes(of: storageID.littleEndian) { objInfo.append(contentsOf: $0) } // StorageID
                withUnsafeBytes(of: UInt16(0x3000).littleEndian) { objInfo.append(contentsOf: $0) } // ObjectFormat (undefined)
                withUnsafeBytes(of: UInt16(0).littleEndian) { objInfo.append(contentsOf: $0) } // ProtectionStatus
                withUnsafeBytes(of: UInt32(file.size > UInt32.max ? 0xFFFFFFFF : UInt32(file.size)).littleEndian) { objInfo.append(contentsOf: $0) } // ObjectCompressedSize
                // Pad remaining fields
                objInfo.append(Data(repeating: 0, count: 38)) // thumb format, dimensions, etc.
                // Filename as MTP string
                let nameUTF16 = Array(file.name.utf16)
                objInfo.append(UInt8(nameUTF16.count + 1)) // String length including null
                for ch in nameUTF16 {
                    withUnsafeBytes(of: ch.littleEndian) { objInfo.append(contentsOf: $0) }
                }
                objInfo.append(contentsOf: [0x00, 0x00]) // null terminator

                // Send as data container
                let infoLen = UInt32(12 + objInfo.count)
                var infoContainer = Data()
                withUnsafeBytes(of: infoLen.littleEndian) { infoContainer.append(contentsOf: $0) }
                withUnsafeBytes(of: UInt16(2).littleEndian) { infoContainer.append(contentsOf: $0) } // Data
                withUnsafeBytes(of: UInt16(0x100C).littleEndian) { infoContainer.append(contentsOf: $0) }
                withUnsafeBytes(of: infoTx.littleEndian) { infoContainer.append(contentsOf: $0) }
                infoContainer.append(objInfo)
                try writeContainer(infoContainer)
                let _ = try readContainer() // response
                print("LOG:ObjectInfo sent for \\(file.name)")

                // SendObject
                let objTx = nextTx()
                try writeContainer(buildCmd(code: 0x100D, tx: objTx))

                // Stream file data in chunks as data container
                let handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
                defer { handle.closeFile() }

                let chunkSize = 1024 * 1024 // 1MB
                var totalSent: UInt64 = 0

                // First chunk includes the data container header
                let firstChunk = handle.readData(ofLength: chunkSize)
                var dataContainer = Data()
                let containerLen = UInt32(12 + file.size)
                withUnsafeBytes(of: containerLen.littleEndian) { dataContainer.append(contentsOf: $0) }
                withUnsafeBytes(of: UInt16(2).littleEndian) { dataContainer.append(contentsOf: $0) } // Data
                withUnsafeBytes(of: UInt16(0x100D).littleEndian) { dataContainer.append(contentsOf: $0) }
                withUnsafeBytes(of: objTx.littleEndian) { dataContainer.append(contentsOf: $0) }
                dataContainer.append(firstChunk)
                try writeContainer(dataContainer)
                totalSent += UInt64(firstChunk.count)
                print("PROGRESS:\\(file.name):\\(totalSent):\\(file.size)")

                // Remaining chunks (raw data, no container header)
                while totalSent < file.size {
                    let chunk = handle.readData(ofLength: chunkSize)
                    if chunk.isEmpty { break }
                    let md = NSMutableData(data: chunk)
                    var bw: Int = 0
                    try outP.__sendIORequest(with: md, bytesTransferred: &bw, completionTimeout: 30.0)
                    totalSent += UInt64(chunk.count)
                    print("PROGRESS:\\(file.name):\\(totalSent):\\(file.size)")
                }

                let _ = try readContainer() // response
                print("LOG:\\(file.name) installed")
            }

            // MTP CloseSession
            let closeTx = nextTx()
            try writeContainer(buildCmd(code: 0x1003, tx: closeTx))
            let _ = try readContainer()
            print("LOG:MTP session closed")

            iface.destroy()
            device.destroy()
            print("OK")
        } catch {
            print("ERROR:\\(error.localizedDescription)")
            exit(1)
        }
        IOObjectRelease(svc)
        """
    }
}
