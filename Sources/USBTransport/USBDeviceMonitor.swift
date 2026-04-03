import Foundation
import CLibUSB
import DBIProtocol

/// Polls for Nintendo Switch USB device attach/detach events.
/// Accepts an injectable pause predicate (Strategy) to avoid polling during transfers.
public final class USBDeviceMonitor: Sendable {
    public enum Event: Sendable {
        case connected
        case disconnected
    }

    private let pollInterval: TimeInterval
    private let shouldPause: @Sendable () -> Bool

    public init(
        pollInterval: TimeInterval = 1.0,
        shouldPause: @escaping @Sendable () -> Bool = { false }
    ) {
        self.pollInterval = pollInterval
        self.shouldPause = shouldPause
    }

    /// Returns an AsyncStream of connection events.
    public func events() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let task = Task.detached { [pollInterval, shouldPause] in
                var wasConnected = false

                while !Task.isCancelled {
                    if !shouldPause() {
                        let isConnected = Self.isSwitchConnected()

                        if isConnected && !wasConnected {
                            continuation.yield(.connected)
                        } else if !isConnected && wasConnected {
                            continuation.yield(.disconnected)
                        }

                        wasConnected = isConnected
                    }

                    try? await Task.sleep(for: .seconds(pollInterval))
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// One-shot check if the Switch is currently connected.
    public static func isSwitchConnected() -> Bool {
        var ctx: OpaquePointer?
        guard libusb_init(&ctx) == 0 else { return false }
        defer { libusb_exit(ctx) }

        let handle = libusb_open_device_with_vid_pid(
            ctx,
            USBTransport.vendorID,
            USBTransport.productID
        )
        if let handle {
            libusb_close(handle)
            return true
        }
        return false
    }
}
