import Foundation
import Darwin

public enum ManualTrashError: Error, LocalizedError {
    case emptySelection, rootSelection, overlappingSelection, requiresRescan, reviewUnavailable
    case invalidPath(String), changed(String), incomplete(String), referenceUnavailable(String), identityUnavailable(String), protectedState(String)
    // Results of the bound move (core input 03). Each names what happened to the object.
    case boundIdentityMismatch(String), moveUnverified(path: String, trashPath: String), unsupportedVolume(String), trashUnavailable(String)
    public var errorDescription: String? {
        switch self {
        case .emptySelection: "Select at least one file or folder."
        case .rootSelection: "The scanned root itself cannot be moved to Trash."
        case .overlappingSelection: "Select a folder or its contents, not both."
        case .requiresRescan: "Scan this folder again before moving selected items to Trash. This inventory lacks current identity or coverage evidence."
        case .reviewUnavailable: "This review is no longer available. Review the selection again."
        case .invalidPath(let path): "This selection is outside the saved scan: \(path)"
        case .changed(let path): "This item or an ancestor changed. Scan again before moving it to Trash: \(path)"
        case .incomplete(let path): "This item's scan coverage is incomplete. Scan again before moving it to Trash: \(path)"
        case .identityUnavailable(let reason): reason
        case .protectedState(let path): "Disk Cleaner's active saved data, or a folder containing it, cannot be moved by this app: \(path)"
        case .referenceUnavailable(let path): "A verified file reference could not be created. Nothing was moved: \(path)"
        case .boundIdentityMismatch(let path): "At the moment of the move this path no longer held the reviewed item. Nothing was moved. Scan again: \(path)"
        case .moveUnverified(let path, let trashPath): "An item from \(path) was moved to Trash, but it could not be confirmed as the reviewed item. Its last known destination in Trash was \(trashPath); it may no longer be there. Inspect Trash and scan again."
        case .unsupportedVolume(let path): "Only items on the same volume as your Trash can be moved by this app. Nothing was moved: \(path)"
        case .trashUnavailable(let reason): "Your Trash folder could not be verified. Nothing was moved: \(reason)"
        }
    }
}
public struct TrashReviewItem: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let bytes: Int64
    public let isDirectory: Bool
}
public struct TrashReview: Sendable, Identifiable {
    public let id: UUID
    public let snapshotID: UUID
    public let root: String
    public let items: [TrashReviewItem]
    public let warning: String
}
public enum TrashItemStatus: String, Sendable { case trashed, failed, notAttempted, unknown }
public struct TrashItemResult: Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let status: TrashItemStatus
    public let message: String
    public let trashURL: URL?
}
public struct TrashBatchResult: Sendable {
    public let items: [TrashItemResult]
    public let requiresRescan: Bool
    public let snapshotInvalidationPersisted: Bool
    public let persistenceError: String?
}

/// The reviewed object: canonical path, full identity and the identity of every
/// directory from `/` to its parent, all taken from the saved snapshot.
public struct TrashTarget: Sendable {
    public let path: String
    public let identity: FileIdentity
    public let ancestors: [InventoryPathIdentity]
}
// Injection supports generated fixtures. Implementations must call `validate`
// synchronously before their move, move only the object identified by `target`
// (or throw) and return the actual destination.
public protocol TrashBackend: Sendable {
    func moveToTrash(_ target: TrashTarget, validate: () throws -> Void) throws -> URL
}
/// Test-only points inside the bound move where generated fixtures simulate an
/// uncoordinated writer. Production construction never sets them.
struct TrashMoveHooks: Sendable {
    var afterValidation: (@Sendable () throws -> Void)?
    var afterParentOpened: (@Sendable () throws -> Void)?
    var beforeRename: (@Sendable () throws -> Void)?
}
/// Moves the reviewed object into the user's Trash with one same-volume
/// `renameatx_np(RENAME_EXCL)` from a descriptor-pinned, identity-verified parent.
///
/// macOS 27.0 returns a plain path URL from `fileReferenceURL()`, and Darwin has no
/// rename-by-descriptor, so the leaf name is still resolved by the kernel inside the
/// pinned parent. Between the final `fstatat` and the rename another process with
/// write access to that one directory can swap the leaf. That gap is not closed.
/// After the move the arrived entry is compared by device and inode; when it does
/// not match, or cannot be observed, it is left in Trash untouched (no automatic
/// move back, which would itself be an unverified two-step move) and reported
/// `moveUnverified` with its Trash path; the caller stops the batch. Ancestor
/// swaps after the parent is opened cannot redirect the move. Cross-volume items
/// fail closed (`unsupportedVolume`); no copy fallback exists. A personal,
/// single-user app accepts this leaf race as an explicit tradeoff (review 03).
public struct SystemTrashBackend: TrashBackend {
    private let trashDirectory: URL?
    let hooks: TrashMoveHooks
    public init() { trashDirectory = nil; hooks = TrashMoveHooks() }
    /// Generated fixtures only: the same primitive with a fixture Trash folder.
    init(trashDirectory: URL, hooks: TrashMoveHooks = TrashMoveHooks()) { self.trashDirectory = trashDirectory; self.hooks = hooks }

    public func moveToTrash(_ target: TrashTarget, validate: () throws -> Void) throws -> URL {
        try validate()
        try hooks.afterValidation?()
        guard InventoryPaths.normalized(target.path) == target.path, target.path != "/",
              let leaf = target.path.split(separator: "/").last.map(String.init) else { throw ManualTrashError.invalidPath(target.path) }
        let trash = try openTrash(device: target.identity.device, path: target.path)
        defer { close(trash.descriptor) }
        let parent = try Self.openVerifiedParent(target)
        defer { close(parent) }
        try hooks.afterParentOpened?()
        // Final confirmation: the entry in the pinned parent is the reviewed object.
        var info = stat()
        guard fstatat(parent, leaf, &info, AT_SYMLINK_NOFOLLOW) == 0 else { throw ManualTrashError.boundIdentityMismatch(target.path) }
        let current = FileIdentity(info)
        guard current.isDirectory || current.isRegular, current == target.identity else { throw ManualTrashError.boundIdentityMismatch(target.path) }
        try hooks.beforeRename?()
        var name: String?
        for attempt in 0..<16 {
            let candidate = Self.trashName(leaf, attempt: attempt)
            if renameatx_np(parent, leaf, trash.descriptor, candidate, UInt32(RENAME_EXCL)) == 0 { name = candidate; break }
            let code = errno
            switch code {
            case EEXIST: continue
            case EXDEV: throw ManualTrashError.unsupportedVolume(target.path)
            case ENOENT: throw ManualTrashError.boundIdentityMismatch(target.path)
            default: throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
            }
        }
        guard let name else { throw POSIXError(.EEXIST) }
        var arrived = stat()
        let verified = fstatat(trash.descriptor, name, &arrived, AT_SYMLINK_NOFOLLOW) == 0 && FileIdentity(arrived).sameObject(as: target.identity)
        let destination = URL(fileURLWithPath: trash.path).appendingPathComponent(name)
        // Unverified is never repaired by another move. The destination is only the
        // last known location; another process may have moved or removed it since.
        guard verified else { throw ManualTrashError.moveUnverified(path: target.path, trashPath: destination.path) }
        return destination
    }
    private func openTrash(device: Int64, path: String) throws -> (descriptor: Int32, path: String) {
        let url: URL
        if let trashDirectory { url = trashDirectory }
        else {
            do { url = try FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false) }
            catch { throw ManualTrashError.trashUnavailable(error.localizedDescription) }
        }
        guard let canonical = try? FileIdentityReader.canonicalDirectoryPath(url.path) else { throw ManualTrashError.trashUnavailable(url.path) }
        // Search-only descriptor: the move never lists Trash, and macOS privacy
        // protection refuses read opens of ~/.Trash for apps without Full Disk Access.
        let fd = open(canonical, O_SEARCH | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw ManualTrashError.trashUnavailable("\(canonical): \(String(cString: strerror(errno)))") }
        var info = stat()
        guard fstat(fd, &info) == 0 else { close(fd); throw ManualTrashError.trashUnavailable(canonical) }
        // Same volume first: renaming is the only supported move, never a copy.
        guard Int64(info.st_dev) == device else { close(fd); throw ManualTrashError.unsupportedVolume(path) }
        guard FileIdentity(info).isDirectory, info.st_uid == geteuid(), info.st_mode & 0o022 == 0 else {
            close(fd); throw ManualTrashError.trashUnavailable("\(canonical) is not a private folder owned by you")
        }
        return (fd, canonical)
    }
    /// Opens each directory from `/` to the parent with no-follow descriptor-relative
    /// opens and requires the recorded object identity at every step.
    static func openVerifiedParent(_ target: TrashTarget) throws -> Int32 {
        let parentPath = InventoryPaths.parent(target.path)
        guard let first = target.ancestors.first, first.path == "/", target.ancestors.last?.path == parentPath else { throw ManualTrashError.requiresRescan }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var info = stat()
        guard fstat(fd, &info) == 0, FileIdentity(info).sameObject(as: first.identity) else { close(fd); throw ManualTrashError.boundIdentityMismatch("/") }
        var current = "/"
        for expected in target.ancestors.dropFirst() {
            guard InventoryPaths.parent(expected.path) == current, let name = expected.path.split(separator: "/").last.map(String.init) else { close(fd); throw ManualTrashError.requiresRescan }
            let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            close(fd)
            guard next >= 0 else { throw ManualTrashError.boundIdentityMismatch(expected.path) }
            fd = next
            guard fstat(fd, &info) == 0, FileIdentity(info).sameObject(as: expected.identity) else { close(fd); throw ManualTrashError.boundIdentityMismatch(expected.path) }
            current = expected.path
        }
        return fd
    }
    /// Original name first; on a collision a Finder-style time suffix, then a unique
    /// suffix. RENAME_EXCL never replaces an existing Trash entry.
    static func trashName(_ leaf: String, attempt: Int) -> String {
        if attempt == 0 { return leaf }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH.mm.ss"
        var suffix = formatter.string(from: Date())
        if attempt > 1 { suffix += " " + String(UUID().uuidString.prefix(8)) }
        let ns = leaf as NSString
        let ext = ns.pathExtension, stem = ns.deletingPathExtension
        return ext.isEmpty || stem.isEmpty ? leaf + " " + suffix : stem + " " + suffix + "." + ext
    }
}

private struct PreparedTrashItem: Sendable { let entry: InventoryEntry; let target: TrashTarget }
private struct PreparedTrashReview: Sendable { let publicReview: TrashReview; let snapshot: InventorySnapshot; let revision: Data; let items: [PreparedTrashItem] }

public actor ManualTrashService {
    private let directory: URL
    private let backend: any TrashBackend
    private let operationGate: InventoryOperationGate
    private var pending: PreparedTrashReview?
    // Explicit backend construction avoids accidentally choosing the OS backend
    // in a fixture/preview. Old example inventories have no eligible identities.
    public init(directory: URL, backend: any TrashBackend, operationGate: InventoryOperationGate = .shared) {
        self.directory = directory; self.backend = backend; self.operationGate = operationGate
    }
    public func discardReview(id: UUID) { if pending?.publicReview.id == id { pending = nil } }
    public func review(snapshot: InventorySnapshot, paths: [String]) async throws -> TrashReview {
        let directory = self.directory
        let prepared = try await operationGate.perform(key: directory.standardizedFileURL.path) {
            let saved = try Self.savedSnapshot(id: snapshot.id, directory: directory)
            return try Self.prepare(snapshot: saved, paths: paths, directory: directory)
        }
        pending = prepared
        return prepared.publicReview
    }
    public func execute(reviewID: UUID) async throws -> TrashBatchResult {
        guard let prepared = pending, prepared.publicReview.id == reviewID else { throw ManualTrashError.reviewUnavailable }
        // Consume before the first suspension, including when dispatch fails.
        pending = nil
        try Task.checkCancellation()
        let directory = self.directory, backend = self.backend
        return try await operationGate.perform(key: directory.path) {
            let current = try Self.savedSnapshot(id: prepared.snapshot.id, directory: directory)
            guard try Self.revision(current) == prepared.revision else { throw ManualTrashError.reviewUnavailable }
            let affected = try Self.commitInvalidation(prepared, directory: directory)
            return Self.execute(prepared, affectedRoots: affected, directory: directory, backend: backend)
        }
    }
    private static func revision(_ snapshot: InventorySnapshot) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }
    static func overlaps(_ a: String, _ b: String) -> Bool { InventoryPaths.contains(root: a, path: b) || InventoryPaths.contains(root: b, path: a) }
    /// Every saved root that is equal to, an ancestor of or a descendant of the
    /// reviewed root or any selected path. Disjoint roots stay valid.
    static func affectedRoots(savedRoots: [String], reviewedRoot: String, paths: [String]) -> Set<String> {
        Set(savedRoots.filter { root in overlaps(root, reviewedRoot) || paths.contains { overlaps(root, $0) } }).union([reviewedRoot])
    }
    private static func commitInvalidation(_ prepared: PreparedTrashReview, directory: URL) throws -> Set<String> {
        let snapshots = try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).read { $0.snapshots }
        let affectedRoots = affectedRoots(savedRoots: snapshots.map(\.root), reviewedRoot: prepared.snapshot.root, paths: prepared.items.map { $0.entry.path })
        let date = Date()
        // Both writes must complete durably before the first move. A marker
        // surviving a ledger failure makes all old observations fail closed.
        try ManualRescanJournal.mark(roots: affectedRoots, at: date, directory: directory)
        try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).locked { ledger in
            guard let current = ledger.snapshots.first(where: { $0.id == prepared.snapshot.id }),
                  try revision(current) == prepared.revision else { throw ManualTrashError.reviewUnavailable }
            for index in ledger.snapshots.indices where affectedRoots.contains(ledger.snapshots[index].root) {
                ledger.snapshots[index] = ledger.snapshots[index].invalidating(at: ledger.snapshots[index].invalidatedAt ?? date)
            }
        }
        return affectedRoots
    }
    private static func savedSnapshot(id: UUID, directory: URL) throws -> InventorySnapshot {
        try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).read { ledger in
            guard let snapshot = ledger.snapshots.first(where: { $0.id == id }), !snapshot.isStale,
                  try ManualRescanJournal.roots(directory: directory)[snapshot.root] == nil else { throw ManualTrashError.requiresRescan }
            return snapshot
        }
    }
    private static func prepare(snapshot: InventorySnapshot, paths: [String], directory: URL) throws -> PreparedTrashReview {
        guard !paths.isEmpty else { throw ManualTrashError.emptySelection }
        guard !snapshot.isStale, snapshot.rootIdentity != nil else { throw ManualTrashError.requiresRescan }
        guard snapshot.rootAncestors != nil else {
            throw ManualTrashError.identityUnavailable(snapshot.errors.first(where: { $0.hasPrefix("Folder identity chain") }) ?? "The folder's identity chain cannot be verified. Manual Trash is unavailable for this scan.")
        }
        guard let volume = snapshot.volumeUUID, !volume.isEmpty else { throw ManualTrashError.identityUnavailable("Volume identity cannot be verified. Manual Trash is unavailable for this scan.") }
        let protectedStore = try FileIdentityReader.canonicalDirectoryPath(directory.path)
        let browser = try InventoryBrowser(snapshot: snapshot)
        let unique = Array(Set(paths)).sorted()
        let selectedPaths = Set(unique)
        for path in unique {
            try Task.checkCancellation()
            guard InventoryPaths.normalized(path) == path, InventoryPaths.contains(root: snapshot.root, path: path) else { throw ManualTrashError.invalidPath(path) }
            guard path != snapshot.root else { throw ManualTrashError.rootSelection }
            guard !InventoryPaths.contains(root: path, path: protectedStore), !InventoryPaths.contains(root: protectedStore, path: path) else { throw ManualTrashError.protectedState(path) }
            var ancestor = InventoryPaths.parent(path)
            while ancestor != snapshot.root && InventoryPaths.contains(root: snapshot.root, path: ancestor) {
                if selectedPaths.contains(ancestor) { throw ManualTrashError.overlappingSelection }
                ancestor = InventoryPaths.parent(ancestor)
            }
        }
        let items = try unique.map { path -> PreparedTrashItem in
            guard let entry = browser.entry(at: path) else { throw ManualTrashError.invalidPath(path) }
            try validate(snapshot: snapshot, entry: entry)
            return PreparedTrashItem(entry: entry, target: try target(snapshot: snapshot, entry: entry))
        }
        let review = TrashReview(id: UUID(), snapshotID: snapshot.id, root: snapshot.root,
            items: items.map { TrashReviewItem(path: $0.entry.path, name: $0.entry.name, bytes: $0.entry.apparentBytes, isDirectory: $0.entry.isDirectory) },
            warning: "Only these selected items will be moved to Trash. Trash does not immediately free disk space. Recover items from Trash manually; this app does not offer Undo.")
        return PreparedTrashReview(publicReview: review, snapshot: snapshot, revision: try revision(snapshot), items: items)
    }
    /// The reviewed object and every recorded directory identity from `/` to its parent.
    private static func target(snapshot: InventorySnapshot, entry: InventoryEntry) throws -> TrashTarget {
        guard let identity = entry.identity, let chain = snapshot.rootAncestors else { throw ManualTrashError.requiresRescan }
        var expected = Dictionary(chain.map { ($0.path, $0.identity) }, uniquingKeysWith: { first, _ in first })
        for directory in snapshot.entries where directory.isDirectory && directory.path != entry.path {
            if let recorded = directory.identity, expected[directory.path] == nil { expected[directory.path] = recorded }
        }
        var ancestors: [InventoryPathIdentity] = []
        var path = InventoryPaths.parent(entry.path)
        while true {
            guard let recorded = expected[path] else { throw ManualTrashError.requiresRescan }
            ancestors.append(InventoryPathIdentity(path: path, identity: recorded))
            if path == "/" { break }
            path = InventoryPaths.parent(path)
        }
        return TrashTarget(path: entry.path, identity: identity, ancestors: ancestors.reversed())
    }
    private static func validateAncestors(snapshot: InventorySnapshot, path: String) throws {
        guard let rootIdentity = snapshot.rootIdentity, let storedRootChain = snapshot.rootAncestors,
              storedRootChain.last?.path == snapshot.root, storedRootChain.last?.identity.sameObject(as: rootIdentity) == true else { throw ManualTrashError.requiresRescan }
        guard let volume = snapshot.volumeUUID, !volume.isEmpty,
              (try? URL(fileURLWithPath: snapshot.root).resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString) == volume else { throw ManualTrashError.changed(snapshot.root) }
        let actual = try FileIdentityReader.rootChain(InventoryPaths.parent(path))
        var expected = Dictionary(storedRootChain.map { ($0.path, $0.identity) }, uniquingKeysWith: { first, _ in first })
        for entry in snapshot.entries where entry.isDirectory {
            if let identity = entry.identity { expected[entry.path] = identity }
        }
        for ancestor in actual {
            guard let recorded = expected[ancestor.path], recorded.sameObject(as: ancestor.identity) else { throw ManualTrashError.changed(ancestor.path) }
        }
        guard actual.contains(where: { $0.path == snapshot.root && $0.identity.sameObject(as: rootIdentity) }) else { throw ManualTrashError.changed(snapshot.root) }
    }
    private static func validate(snapshot: InventorySnapshot, entry: InventoryEntry) throws {
        guard !snapshot.isStale, let expected = entry.identity else { throw ManualTrashError.requiresRescan }
        guard expected.isDirectory == entry.isDirectory, expected.isDirectory || expected.isRegular else { throw ManualTrashError.changed(entry.path) }
        guard entry.coverage == .complete else { throw ManualTrashError.incomplete(entry.path) }
        guard expected.device == snapshot.rootIdentity?.device else { throw ManualTrashError.changed(entry.path) }
        try validateAncestors(snapshot: snapshot, path: entry.path)
        guard try FileIdentityReader.at(entry.path) == expected else { throw ManualTrashError.changed(entry.path) }
        // A selected directory needs a complete, unchanged subtree. Directory
        // timestamps alone do not establish that descendants are unchanged.
        if entry.isDirectory {
            for child in snapshot.entries where child.path != entry.path && InventoryPaths.contains(root: entry.path, path: child.path) {
                try Task.checkCancellation()
                guard child.coverage == .complete, let identity = child.identity else { throw ManualTrashError.incomplete(child.path) }
                guard try FileIdentityReader.at(child.path) == identity else { throw ManualTrashError.changed(child.path) }
            }
        }
    }
    private static func execute(_ prepared: PreparedTrashReview, affectedRoots: Set<String>, directory: URL, backend: any TrashBackend) -> TrashBatchResult {
        var outcomes: [TrashItemResult] = []
        // Invalidation was committed before dispatch, even if every move fails.
        let needsRescan = true
        var stop = false
        for item in prepared.items {
            let path = item.entry.path
            if stop || Task.isCancelled {
                outcomes.append(TrashItemResult(path: path, status: .notAttempted, message: "Not attempted. Review the current inventory before continuing.", trashURL: nil)); continue
            }
            do {
                try validate(snapshot: prepared.snapshot, entry: item.entry)
            } catch {
                outcomes.append(TrashItemResult(path: path, status: .notAttempted, message: error.localizedDescription, trashURL: nil)); continue
            }
            do {
                let destination = try backend.moveToTrash(item.target) {
                    try validate(snapshot: prepared.snapshot, entry: item.entry)
                }
                guard let expected = item.entry.identity,
                      let moved = try? FileIdentityReader.at(destination.path), expected.sameObject(as: moved),
                      !((try? FileIdentityReader.at(path))?.sameObject(as: expected) ?? false) else {
                    stop = true
                    outcomes.append(TrashItemResult(path: path, status: .unknown, message: "The move could not be verified. Inspect Trash and scan again; no capacity gain was assumed.", trashURL: destination)); continue
                }
                do { try validateAncestors(snapshot: prepared.snapshot, path: path) }
                catch {
                    stop = true
                    outcomes.append(TrashItemResult(path: path, status: .unknown, message: "The selected object reached Trash, but its source scope changed during the move. Inspect the result and scan again.", trashURL: destination)); continue
                }
                outcomes.append(TrashItemResult(path: path, status: .trashed, message: "Moved to Trash. Disk space is not reclaimed until Trash is emptied separately.", trashURL: destination))
            } catch let error as ManualTrashError {
                // Errors from the bound move say exactly what happened to the object.
                switch error {
                case .moveUnverified(_, let trashPath):
                    stop = true
                    outcomes.append(TrashItemResult(path: path, status: .unknown, message: error.localizedDescription, trashURL: URL(fileURLWithPath: trashPath)))
                case .unsupportedVolume, .trashUnavailable:
                    outcomes.append(TrashItemResult(path: path, status: .notAttempted, message: error.localizedDescription, trashURL: nil))
                default:
                    // Refused before any rename: nothing moved. A concurrent change stops the batch.
                    stop = true
                    outcomes.append(TrashItemResult(path: path, status: .notAttempted, message: error.localizedDescription, trashURL: nil))
                }
            } catch {
                let intact = (try? FileIdentityReader.at(path)) == item.entry.identity
                if !intact { stop = true }
                outcomes.append(TrashItemResult(path: path, status: intact ? .failed : .unknown,
                    message: intact ? "Could not move this item: \(error.localizedDescription)" : "The outcome is uncertain: \(error.localizedDescription). Inspect Trash and scan again.", trashURL: nil))
            }
        }
        var persisted = true
        var persistenceError: String?
        do {
            let marked = try ManualRescanJournal.roots(directory: directory)
            guard affectedRoots.allSatisfy({ marked[$0] != nil }) else { throw ManualTrashError.requiresRescan }
            let all = try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).read { $0.snapshots }
            guard all.contains(where: { $0.id == prepared.snapshot.id }),
                  all.filter({ affectedRoots.contains($0.root) }).allSatisfy(\.isStale) else { throw ManualTrashError.requiresRescan }
        } catch {
            persisted = false
            persistenceError = "Inventory invalidation could not be verified after the action. Do not reuse this inventory: \(error.localizedDescription)"
        }
        return TrashBatchResult(items: outcomes, requiresRescan: needsRescan, snapshotInvalidationPersisted: persisted, persistenceError: persistenceError)
    }
}

extension InventorySnapshot {
    func invalidating(at date: Date) -> Self {
        Self(id: id, root: root, createdAt: createdAt, entries: entries, errors: errors, capacity: capacity,
             scannerVersion: scannerVersion, volumeUUID: volumeUUID, rootDevice: rootDevice, rootInode: rootInode,
             rootIdentity: rootIdentity, rootAncestors: rootAncestors, invalidatedAt: date)
    }
}
