import Foundation

/// Lets transports classify their errors without the protocol layer depending on them
/// (Dependency Inversion). DBISession uses this to tell "Switch is idle" apart from real failures.
public protocol TransportError: Error {
    /// True when the read/write simply ran out of time with no data — the link is still healthy.
    var isTimeout: Bool { get }
}
