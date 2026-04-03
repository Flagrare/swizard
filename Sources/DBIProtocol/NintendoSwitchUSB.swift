import Foundation

/// Nintendo Switch USB identifiers for different DBI modes.
public enum NintendoSwitchUSB {
    public static let vendorID: UInt16 = 0x057E

    /// Product ID when DBI is in MTP responder mode.
    public static let mtpProductID: UInt16 = 0x201D

    /// Product ID when DBI is in backend mode.
    public static let backendProductID: UInt16 = 0x3000
}
