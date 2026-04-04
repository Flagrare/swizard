import Foundation

/// Raw storage info parsed from MTP GetStorageInfo response.
public struct MTPStorageInfo: Sendable, Equatable {
    public let id: UInt32
    public let name: String

    public init(id: UInt32, name: String) {
        self.id = id
        self.name = name
    }
}

/// A valid install destination on the Switch (Value Object).
/// Represents a DBI MTP storage that accepts game files for installation.
public struct MTPInstallDestination: Sendable, Equatable, Identifiable, Hashable {
    public var id: UInt32 { storageID }
    public let storageID: UInt32
    public let rawName: String

    public init(storageID: UInt32, rawName: String) {
        self.storageID = storageID
        self.rawName = rawName
    }

    /// User-friendly name with numeric prefix stripped (e.g., "5: SD Card install" → "SD Card install").
    public var displayName: String {
        if let colonIndex = rawName.firstIndex(of: ":") {
            let afterColon = rawName[rawName.index(after: colonIndex)...]
            return afterColon.trimmingCharacters(in: .whitespaces)
        }
        return rawName
    }

    /// Whether this is an SD card install destination (preferred over NAND).
    public var isSDInstall: Bool {
        rawName.lowercased().contains("sd")
    }

    // MARK: - Factory methods

    /// Filter a list of storages to only those that are install destinations.
    /// Filter a list of storages to only those that are install destinations.
    /// Matches storages whose name ends with "install" (case-insensitive),
    /// excluding "Installed games" which is a browse storage.
    public static func fromStorages(_ storages: [MTPStorageInfo]) -> [MTPInstallDestination] {
        storages
            .filter { name in
                let lower = name.name.lowercased()
                // Must end with "install" — excludes "Installed games"
                return lower.hasSuffix(DBIMTPConstants.installKeyword)
            }
            .map { MTPInstallDestination(storageID: $0.id, rawName: $0.name) }
    }

    /// Pick the best default destination — prefer SD over NAND.
    public static func defaultDestination(from destinations: [MTPInstallDestination]) -> MTPInstallDestination? {
        destinations.first(where: { $0.isSDInstall }) ?? destinations.first
    }
}
