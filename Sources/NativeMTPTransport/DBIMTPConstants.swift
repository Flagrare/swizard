import Foundation

/// Constants for DBI's MTP storage and folder naming conventions.
/// These are searched case-insensitively to support different DBI versions and languages.
public enum DBIMTPConstants {
    /// Keywords that identify an SD card install storage in DBI's MTP.
    /// DBI typically names it "5: SD Card install" but this varies by version.
    public static let sdInstallKeywords = ["sd", "install"]

    /// Fallback keyword for any install storage (NAND or SD).
    public static let installKeyword = "install"

    /// MTP ObjectFormat code for undefined/generic files.
    public static let objectFormatUndefined: UInt16 = 0x3000

    /// MTP operation codes used in the privileged script.
    public enum Operation {
        public static let openSession: UInt16 = 0x1002
        public static let closeSession: UInt16 = 0x1003
        public static let getStorageIDs: UInt16 = 0x1004
        public static let getStorageInfo: UInt16 = 0x1005
        public static let getObjectHandles: UInt16 = 0x1007
        public static let getObjectInfo: UInt16 = 0x1008
        public static let sendObjectInfo: UInt16 = 0x100C
        public static let sendObject: UInt16 = 0x100D
    }
}
