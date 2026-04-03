import Foundation

/// DBI0 protocol constants matching the reference Python implementation.
public enum DBICommand: UInt32, Sendable {
    case exit = 0
    case fileRange = 2
    case list = 3
}

public enum DBICommandType: UInt32, Sendable {
    case request = 0
    case response = 1
    case ack = 2
}

public enum DBIConstants {
    public static let magic = Data("DBI0".utf8)
    public static let headerSize = 16
    public static let chunkSize = 0x100000 // 1 MB
}
