import Foundation

/// Runs a USB device claim operation with admin privileges via osascript.
/// This prompts the user for their password once, then the helper claims
/// the device and releases it for our process to use.
///
/// The approach: run a small Swift snippet as root that does DeviceCapture,
/// configures the device, and exits — releasing all kernel drivers.
/// Then our process can immediately open the device and interface.
public enum PrivilegedUSBClaim {

    /// Claim a USB device by VID/PID with admin privileges.
    /// Prompts the user for their admin password.
    /// After this returns, the device is available for normal IOUSBHost access.
    public static func claimDevice(vendorID: UInt16, productID: UInt16) async throws {
        let script = """
        import Foundation; import IOKit; import IOUSBHost
        guard let m = IOServiceMatching("IOUSBHostDevice") else { exit(1) }
        var it: io_iterator_t = 0; IOServiceGetMatchingServices(0, m, &it)
        while true { let s = IOIteratorNext(it); guard s != 0 else { break }
          let v = IORegistryEntryCreateCFProperty(s, "idVendor" as CFString, nil, 0)?.takeRetainedValue() as? Int ?? 0
          let p = IORegistryEntryCreateCFProperty(s, "idProduct" as CFString, nil, 0)?.takeRetainedValue() as? Int ?? 0
          if v == \(vendorID) && p == \(productID) {
            let d = try IOUSBHostDevice(__ioService: s, options: .deviceCapture, queue: .main, interestHandler: nil)
            try d.__configure(withValue: 1, matchInterfaces: false)
            Thread.sleep(forTimeInterval: 0.5)
            d.destroy()
            print("OK")
          }; IOObjectRelease(s)
        }; IOObjectRelease(it)
        """

        let escapedScript = script
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")

        let osascript = """
        do shell script "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift -e '\(escapedScript)' 2>&1" with administrator privileges
        """

        let result = try await runOsascript(osascript)

        guard result.contains("OK") else {
            throw IOUSBHostError.claimFailed("Privileged claim failed: \(result)")
        }
    }

    private static func runOsascript(_ script: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                process.arguments = ["-e", script]

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: IOUSBHostError.claimFailed(output))
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
