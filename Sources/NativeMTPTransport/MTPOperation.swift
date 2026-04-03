import Foundation

/// MTP operation codes for the commands we need.
public enum MTPOperation: UInt16, Sendable {
    case getDeviceInfo    = 0x1001
    case openSession      = 0x1002
    case closeSession     = 0x1003
    case getStorageIDs    = 0x1004
    case getStorageInfo   = 0x1005
    case getObjectHandles = 0x1007
    case getObjectInfo    = 0x1008
    case getObject        = 0x1009
    case sendObjectInfo   = 0x100C
    case sendObject       = 0x100D
    case deleteObject     = 0x100B
}
