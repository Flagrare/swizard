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
        targetStorageID: UInt32? = nil,
        onProgress: @escaping ProgressHandler,
        onLog: @escaping LogHandler
    ) async throws {
        // Copy files to /tmp so the privileged (root) process can access them.
        // macOS TCC blocks root from reading user directories.
        let stagingDir = FileManager.default.temporaryDirectory.appendingPathComponent("swizard_install_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: stagingDir) }

        var stagedFiles: [FileToInstall] = []
        for file in files {
            let source = URL(fileURLWithPath: file.path)
            let dest = stagingDir.appendingPathComponent(file.name)
            onLog("Staging \(file.name) for privileged transfer...")
            try FileManager.default.copyItem(at: source, to: dest)
            stagedFiles.append(FileToInstall(path: dest.path, name: file.name, size: file.size))
        }

        let cSource = Self.buildScript(vendorID: vendorID, productID: productID, files: stagedFiles, targetStorageID: targetStorageID)

        onLog("Requesting admin privileges...")

        // Write C source to temp file, compile with cc, then run
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("swizard_mtp_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sourceFile = tempDir.appendingPathComponent("mtp_install.c")
        let binaryFile = tempDir.appendingPathComponent("mtp_install")
        try cSource.write(to: sourceFile, atomically: true, encoding: .utf8)

        // Compile with both libmtp and libusb
        let compileCmd = "cc -o \\\"\(binaryFile.path)\\\" \\\"\(sourceFile.path)\\\" -I/opt/homebrew/include -L/opt/homebrew/lib -lmtp -lusb-1.0 2>&1 && \\\"\(binaryFile.path)\\\" 2>&1"
        let osascript = "do shell script \"\(compileCmd)\" with administrator privileges"

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

    /// Builds a shell script that runs libmtp as root.
    /// libmtp handles the entire MTP protocol correctly (it's the reference implementation).
    /// As root, libusb_detach_kernel_driver succeeds — no IOUSBHost needed.
    public static func buildScript(
        vendorID: UInt16,
        productID: UInt16,
        files: [FileToInstall],
        targetStorageID: UInt32? = nil
    ) -> String {
        // Build a shell script that uses mtp-sendfile or a Python/Swift helper with libmtp
        // Since libmtp is a C library, we use a small C program compiled and run inline
        let fileArgs = files.map { file in
            "\(file.path)\t\(file.name)\t\(file.size)"
        }.joined(separator: "\n")

        let storageArg = targetStorageID.map { String($0) } ?? ""

        // Use a Python script with pymtp/libmtp or compile a small C program
        // Simplest approach: use mtp-tools command-line utilities
        // But libmtp doesn't ship CLI tools via brew. Let's use a C program.

        // Actually, the simplest proven approach: compile a small C file that uses libmtp API
        return buildLibmtpCScript(files: files, targetStorageID: targetStorageID)
    }

    private static func buildLibmtpCScript(
        files: [FileToInstall],
        targetStorageID: UInt32?
    ) -> String {
        let fileEntries = files.map { file in
            "{\"\(file.path)\", \"\(file.name)\", \(file.size)}"
        }.joined(separator: ",\n    ")

        let storageOverride = targetStorageID.map { "uint32_t target_storage = \($0);" } ?? "uint32_t target_storage = 0;"
        let hasOverride = targetStorageID != nil ? "1" : "0"

        return """
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>
        #include <libusb-1.0/libusb.h>
        #include <libmtp.h>

        typedef struct { const char *path; const char *name; uint64_t size; } FileEntry;

        int main() {
            FileEntry files[] = {
                \(fileEntries.isEmpty ? "{NULL, NULL, 0}" : fileEntries)
            };
            int file_count = \(files.count);
            \(storageOverride)
            int has_override = \(hasOverride);

            // Step 1: Use libusb to detach kernel driver (requires root)
            libusb_context *usb_ctx;
            libusb_init(&usb_ctx);
            libusb_device_handle *usb_handle = libusb_open_device_with_vid_pid(usb_ctx, 0x057E, 0x201D);
            if (usb_handle) {
                libusb_set_auto_detach_kernel_driver(usb_handle, 1);
                int dr = libusb_detach_kernel_driver(usb_handle, 0);
                printf("LOG:Kernel driver detach: %d\\n", dr); fflush(stdout);
                // Release but keep auto-detach — kernel driver stays detached briefly
                libusb_close(usb_handle);
            }
            libusb_exit(usb_ctx);
            printf("LOG:Kernel driver released\\n"); fflush(stdout);

            // Step 2: Now use libmtp while kernel driver is still detached
            LIBMTP_Init();
            printf("LOG:libmtp initialized\\n"); fflush(stdout);

            LIBMTP_raw_device_t *rawdevs = NULL;
            int numdevs = 0;
            LIBMTP_error_number_t err = LIBMTP_Detect_Raw_Devices(&rawdevs, &numdevs);
            if (err != LIBMTP_ERROR_NONE || numdevs == 0) {
                printf("ERROR:No MTP devices found after driver detach\\n");
                return 1;
            }
            printf("LOG:Found %d MTP device(s)\\n", numdevs); fflush(stdout);

            LIBMTP_mtpdevice_t *device = LIBMTP_Open_Raw_Device_Uncached(&rawdevs[0]);
            free(rawdevs);
            if (!device) {
                printf("ERROR:Failed to open MTP device\\n");
                return 1;
            }
            printf("LOG:Device opened via libmtp\\n"); fflush(stdout);

            // Find install storage
            LIBMTP_Get_Storage(device, LIBMTP_STORAGE_SORTBY_NOTSORTED);
            LIBMTP_devicestorage_t *install_storage = NULL;
            LIBMTP_devicestorage_t *storage = device->storage;

            if (has_override) {
                while (storage) {
                    if (storage->id == target_storage) { install_storage = storage; break; }
                    storage = storage->next;
                }
            }

            if (!install_storage) {
                // Search by name — hasSuffix "install" (case-insensitive)
                storage = device->storage;
                while (storage) {
                    const char *desc = storage->StorageDescription ? storage->StorageDescription : "";
                    printf("LOG:  Storage %u: %s\\n", storage->id, desc); fflush(stdout);
                    int len = strlen(desc);
                    if (len >= 7) {
                        const char *suffix = desc + len - 7; // "install" = 7 chars
                        if (strcasecmp(suffix, "install") == 0) {
                            install_storage = storage;
                            printf("LOG:  → Install storage!\\n"); fflush(stdout);
                            // Prefer SD over NAND
                            if (strcasestr(desc, "sd") || strcasestr(desc, "SD")) break;
                        }
                    }
                    storage = storage->next;
                }
            }

            if (!install_storage) {
                printf("ERROR:No install storage found\\n");
                LIBMTP_Release_Device(device);
                return 1;
            }
            printf("LOG:Using storage %u: %s\\n", install_storage->id,
                   install_storage->StorageDescription ? install_storage->StorageDescription : "?");
            fflush(stdout);

            // Send each file
            for (int i = 0; i < file_count; i++) {
                if (!files[i].path) continue;
                printf("LOG:Installing %s (%llu bytes)\\n", files[i].name, files[i].size);
                fflush(stdout);

                LIBMTP_file_t *fileMeta = LIBMTP_new_file_t();
                fileMeta->filename = strdup(files[i].name);
                fileMeta->filesize = files[i].size;
                fileMeta->filetype = LIBMTP_FILETYPE_UNKNOWN;
                fileMeta->parent_id = 0;
                fileMeta->storage_id = install_storage->id;

                int ret = LIBMTP_Send_File_From_File(
                    device,
                    files[i].path,
                    fileMeta,
                    NULL, // progress callback
                    NULL  // callback data
                );

                LIBMTP_destroy_file_t(fileMeta);

                if (ret != 0) {
                    LIBMTP_error_t *errstack = LIBMTP_Get_Errorstack(device);
                    printf("ERROR:Transfer failed for %s: %s\\n", files[i].name,
                           errstack ? errstack->error_text : "unknown");
                    LIBMTP_Clear_Errorstack(device);
                    LIBMTP_Release_Device(device);
                    return 1;
                }

                printf("LOG:%s installed\\n", files[i].name);
                printf("PROGRESS:%s:%llu:%llu\\n", files[i].name, files[i].size, files[i].size);
                fflush(stdout);
            }

            LIBMTP_Release_Device(device);
            printf("OK\\n");
            return 0;
        }
        """
    }
}
