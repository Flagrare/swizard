import Foundation
import CLibUSB
import DBIProtocol

/// Adapter: wraps libusb's blocking C API into Swift async TransportProtocol.
/// All libusb calls run on a dedicated serial DispatchQueue to avoid blocking
/// the Swift cooperative thread pool.
public final class USBTransport: TransportProtocol, @unchecked Sendable {
    private static let usbQueue = DispatchQueue(label: "com.swizard.usb", qos: .userInitiated)

    // Nintendo Switch USB identifiers
    static let vendorID: UInt16 = 0x057E
    static let productID: UInt16 = 0x3000

    private var context: OpaquePointer?
    private var handle: OpaquePointer?
    private var inEndpoint: UInt8 = 0x81
    private var outEndpoint: UInt8 = 0x01
    private let timeout: UInt32 = 5000 // 5 seconds

    public init() {}

    public func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Self.usbQueue.async { [self] in
                do {
                    try self.initializeAndOpen()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func disconnect() async throws {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Self.usbQueue.async { [self] in
                self.cleanup()
                continuation.resume()
            }
        }
    }

    public func read(maxLength: Int) async throws -> Data {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, any Error>) in
            Self.usbQueue.async { [self] in
                guard let handle = self.handle else {
                    continuation.resume(throwing: USBError.notConnected)
                    return
                }

                var buffer = [UInt8](repeating: 0, count: maxLength)
                var transferred: Int32 = 0

                let result = libusb_bulk_transfer(
                    handle,
                    self.inEndpoint,
                    &buffer,
                    Int32(maxLength),
                    &transferred,
                    self.timeout
                )

                if result == LIBUSB_ERROR_TIMEOUT.rawValue {
                    continuation.resume(throwing: USBError.timeout)
                } else if result == LIBUSB_ERROR_NO_DEVICE.rawValue || result == LIBUSB_ERROR_PIPE.rawValue {
                    continuation.resume(throwing: USBError.disconnected)
                } else if result < 0 {
                    continuation.resume(throwing: USBError.transferFailed(result))
                } else {
                    continuation.resume(returning: Data(buffer[0..<Int(transferred)]))
                }
            }
        }
    }

    public func write(_ data: Data) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            Self.usbQueue.async { [self] in
                guard let handle = self.handle else {
                    continuation.resume(throwing: USBError.notConnected)
                    return
                }

                var bytes = [UInt8](data)
                var offset = 0

                // Write in chunks to handle large transfers
                while offset < bytes.count {
                    let remaining = bytes.count - offset
                    let chunkSize = min(remaining, DBIConstants.chunkSize)
                    var transferred: Int32 = 0

                    let result = bytes.withUnsafeMutableBufferPointer { buffer in
                        libusb_bulk_transfer(
                            handle,
                            self.outEndpoint,
                            buffer.baseAddress! + offset,
                            Int32(chunkSize),
                            &transferred,
                            self.timeout
                        )
                    }

                    if result == LIBUSB_ERROR_TIMEOUT.rawValue {
                        continuation.resume(throwing: USBError.timeout)
                        return
                    } else if result == LIBUSB_ERROR_NO_DEVICE.rawValue || result == LIBUSB_ERROR_PIPE.rawValue {
                        continuation.resume(throwing: USBError.disconnected)
                        return
                    } else if result < 0 {
                        continuation.resume(throwing: USBError.transferFailed(result))
                        return
                    }

                    offset += Int(transferred)
                }

                continuation.resume()
            }
        }
    }

    // MARK: - Private

    private func initializeAndOpen() throws {
        var ctx: OpaquePointer?
        let initResult = libusb_init(&ctx)
        guard initResult == 0 else {
            throw USBError.transferFailed(initResult)
        }
        self.context = ctx

        let dev = libusb_open_device_with_vid_pid(ctx, Self.vendorID, Self.productID)
        guard let dev else {
            throw USBError.deviceNotFound
        }
        self.handle = dev

        // Detach kernel driver if active
        if libusb_kernel_driver_active(dev, 0) == 1 {
            libusb_detach_kernel_driver(dev, 0)
        }

        let claimResult = libusb_claim_interface(dev, 0)
        guard claimResult == 0 else {
            throw USBError.claimFailed(claimResult)
        }

        // Discover endpoints from the device descriptor
        try discoverEndpoints(device: dev)
    }

    private func discoverEndpoints(device: OpaquePointer) throws {
        guard let rawDevice = libusb_get_device(device) else { return }

        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        guard libusb_get_active_config_descriptor(rawDevice, &config) == 0,
              let config else { return }
        defer { libusb_free_config_descriptor(config) }

        // Find the first interface's endpoints
        guard config.pointee.bNumInterfaces > 0 else { return }
        let interface = config.pointee.interface[0]
        guard interface.num_altsetting > 0 else { return }
        let altsetting = interface.altsetting[0]

        for i in 0..<Int(altsetting.bNumEndpoints) {
            let endpoint = altsetting.endpoint[i]
            let address = endpoint.bEndpointAddress

            if address & 0x80 != 0 {
                self.inEndpoint = address  // IN endpoint
            } else {
                self.outEndpoint = address // OUT endpoint
            }
        }
    }

    private func cleanup() {
        if let handle {
            libusb_release_interface(handle, 0)
            libusb_close(handle)
        }
        if let context {
            libusb_exit(context)
        }
        self.handle = nil
        self.context = nil
    }

    deinit {
        cleanup()
    }
}
