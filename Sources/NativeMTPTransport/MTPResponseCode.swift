import Foundation

/// MTP response codes returned in Response containers.
public enum MTPResponseCode: UInt16, Sendable {
    case ok                    = 0x2001
    case generalError          = 0x2002
    case sessionNotOpen        = 0x2003
    case invalidTransactionID  = 0x2004
    case operationNotSupported = 0x2005
    case parameterNotSupported = 0x2006
    case incompleteTransfer    = 0x2007
    case invalidStorageID      = 0x2008
    case invalidObjectHandle   = 0x2009
    case storeFull             = 0x200C
    case invalidParentObject   = 0x201A
    case sessionAlreadyOpen    = 0x201E

    /// Whether this response indicates success.
    public var isSuccess: Bool { self == .ok }
}
