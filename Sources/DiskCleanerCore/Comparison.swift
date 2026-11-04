import Foundation

public struct InventoryChange: Sendable {
    public let path: String
    public let previousBytes: Int64
    public let currentBytes: Int64
    public let previousDate: Date
    public let currentDate: Date
    public var changeBytes: Int64 { currentBytes - previousBytes }
}
public func compareSnapshots(_ previous: InventorySnapshot, _ current: InventorySnapshot) -> [InventoryChange] {
    // Only apparent-byte changes for independently complete entries are comparable.
    // The optional identity fields exclude legacy snapshots and unknown volumes.
    guard !previous.isStale, !current.isStale,
          previous.root == current.root,
          previous.scannerVersion == 2, current.scannerVersion == 2,
          let volume = previous.volumeUUID, !volume.isEmpty, volume == current.volumeUUID,
          let device = previous.rootDevice, device == current.rootDevice,
          let inode = previous.rootInode, inode == current.rootInode else { return [] }
    let previousEntries = Dictionary(previous.entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
    return current.entries.compactMap { entry in
        guard entry.coverage == .complete, let old = previousEntries[entry.path], old.coverage == .complete, old.isDirectory == entry.isDirectory else { return nil }
        return InventoryChange(path: entry.path, previousBytes: old.apparentBytes, currentBytes: entry.apparentBytes, previousDate: previous.createdAt, currentDate: current.createdAt)
    }
}

/// Discovery cues only: file modification dates do not imply safety to delete.
/// Folder metadata is intentionally excluded: its timestamp does not cover descendants.
public func largeUnchangedFiles(in snapshot: InventorySnapshot, before: Date) -> [InventoryEntry] {
    snapshot.entries.filter { entry in
        guard !entry.isDirectory, entry.coverage == .complete, let modifiedAt = entry.modifiedAt else { return false }
        return modifiedAt < before
    }.sorted { $0.apparentBytes > $1.apparentBytes }
}
