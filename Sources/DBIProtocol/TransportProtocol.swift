import Foundation

/// Abstraction for USB communication (Strategy pattern).
/// Enables swapping real USB transport for mock in tests (Liskov Substitution).
public protocol TransportProtocol: Sendable {
    func connect() async throws
    func disconnect() async throws
    func read(maxLength: Int) async throws -> Data
    func write(_ data: Data) async throws
}
