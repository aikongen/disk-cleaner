import Foundation
import Darwin
import Testing
@testable import DiskCleanerCore

// Regular tests move generated fixtures only, into a generated fixture Trash folder.
// Most use the production bound-rename primitive (SystemTrashBackend with a fixture
// Trash folder); a fake backend remains only for injected failures. Only
// `realUserTrashSmokeMovesOneGeneratedFile` touches the real user Trash, with one
// generated file, never enumerating it; it runs only with DISK_CLEANER_RUN_REAL_TRASH_SMOKE=1 and leaves its file in Trash.
private struct FixtureTrashBackend: TrashBackend {
    let destination: URL
    var failNames = Set<String>()
    var missingDestination = false
    var afterMove: (@Sendable () throws -> Void)?
    func moveToTrash(_ target: TrashTarget, validate: () throws -> Void) throws -> URL {
        let source = URL(fileURLWithPath: target.path)
        try validate()
        if failNames.contains(source.lastPathComponent) { throw CocoaError(.fileWriteNoPermission) }
        let moved = destination.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.moveItem(at: source, to: moved)
        try afterMove?()
        return missingDestination ? destination.appendingPathComponent("missing-\(UUID().uuidString)") : moved
    }
}
private struct TrashFixture {
    let root: URL; let input: URL; let state: URL; let output: URL
    init() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-trash-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = URL(fileURLWithPath: try FileIdentityReader.canonicalDirectoryPath(root.path))
        input = self.root.appendingPathComponent("input"); state = self.root.appendingPathComponent("state"); output = self.root.appendingPathComponent("fixture-trash")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
    func write(_ path: String, _ text: String = "fixture") throws -> URL {
        let url = input.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url); return url
    }
    func scan() async throws -> InventorySnapshot { try await InventoryStore(directory: state).scan(root: input) }
    func scan(_ url: URL) async throws -> InventorySnapshot { try await InventoryStore(directory: state).scan(root: url) }
    func bound(_ hooks: TrashMoveHooks = TrashMoveHooks()) -> SystemTrashBackend { SystemTrashBackend(trashDirectory: output, hooks: hooks) }
    func service(_ backend: (any TrashBackend)? = nil) -> ManualTrashService { ManualTrashService(directory: state, backend: backend ?? bound()) }
    func trashNames() throws -> [String] { try FileManager.default.contentsOfDirectory(atPath: output.path).sorted() }
    func clean() { try? FileManager.default.removeItem(at: root) }
}
private func inode(_ url: URL) throws -> UInt64 { try FileIdentityReader.at(url.path).inode }
@Test func explicitReviewedBatchMovesOnlySelectedFixturesAndInvalidatesInventory() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let a = try f.write("a.txt"), b = try f.write("b.txt"), keep = try f.write("keep.txt")
    let inodes = [try inode(a), try inode(b)]
    let snapshot = try await f.scan(); let service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [a.path, b.path])
    #expect(review.items.map(\.path) == [a.path, b.path])
    #expect(review.warning.contains("does not immediately"))
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.map(\.status) == [.trashed, .trashed])
    #expect(result.requiresRescan && result.snapshotInvalidationPersisted)
    // The bound primitive moved exactly the reviewed objects into the fixture Trash.
    let arrived = try result.items.map { try inode(try #require($0.trashURL)) }
    #expect(arrived == inodes)
    #expect(try f.trashNames() == ["a.txt", "b.txt"])
    #expect(FileManager.default.fileExists(atPath: keep.path))
    #expect(!FileManager.default.fileExists(atPath: a.path))
    let persisted = try await InventoryStore(directory: f.state).snapshots()
    #expect(persisted.first?.isStale == true)
    do { _ = try await service.execute(reviewID: review.id); Issue.record("review replay executed") } catch ManualTrashError.reviewUnavailable { }
    do { _ = try await service.review(snapshot: snapshot, paths: [keep.path]); Issue.record("stale snapshot authorized another move") } catch ManualTrashError.requiresRescan { }
}
@Test func rootEscapeOverlapAndLegacySelectionsFailBeforeAnyMove() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("a/file"), sibling = try f.write("a-b")
    let snapshot = try await f.scan(); let service = f.service()
    do { _ = try await service.review(snapshot: snapshot, paths: [f.input.path]); Issue.record("root accepted") } catch ManualTrashError.rootSelection { }
    do { _ = try await service.review(snapshot: snapshot, paths: [f.input.path + "-other/file"]); Issue.record("prefix escape accepted") } catch ManualTrashError.invalidPath { }
    do { _ = try await service.review(snapshot: snapshot, paths: [f.input.appendingPathComponent("a").path, sibling.path, file.path]); Issue.record("nonadjacent overlap accepted") } catch ManualTrashError.overlappingSelection { }
    var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
    object.removeValue(forKey: "rootIdentity"); object.removeValue(forKey: "rootAncestors")
    if var entries = object["entries"] as? [[String: Any]] {
        for index in entries.indices { entries[index].removeValue(forKey: "identity") }
        object["entries"] = entries
    }
    let legacy = try JSONDecoder().decode(InventorySnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    #expect(try InventoryBrowser(snapshot: legacy).entry(at: file.path)?.identity == nil)
    try DiskFile(directory: f.state, name: "snapshots.json", fallback: SnapshotLedger()).locked { $0.snapshots = [legacy] }
    do { _ = try await service.review(snapshot: legacy, paths: [file.path]); Issue.record("legacy snapshot accepted") } catch ManualTrashError.requiresRescan { }
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
}
@Test func fileReplacementAndSymlinkSwapAfterReviewNeverReachFixtureTrash() async throws {
    for symlink in [false, true] {
        let f = try TrashFixture(); defer { f.clean() }
        let file = try f.write("selected"); let outside = f.root.appendingPathComponent("outside")
        try Data("outside".utf8).write(to: outside)
        let snapshot = try await f.scan(); let service = f.service()
        let review = try await service.review(snapshot: snapshot, paths: [file.path])
        try FileManager.default.removeItem(at: file)
        if symlink { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside) }
        else { try Data("replacement".utf8).write(to: file) }
        let result = try await service.execute(reviewID: review.id)
        #expect(result.items.first?.status == .notAttempted)
        #expect(result.requiresRescan)
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
        #expect(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
    }
}
@Test func ancestorDirectorySwapAfterReviewIsRejected() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("folder/selected")
    let snapshot = try await f.scan(); let service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    try FileManager.default.moveItem(at: file.deletingLastPathComponent(), to: f.input.appendingPathComponent("original-folder"))
    _ = try f.write("folder/selected", "replacement")
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .notAttempted)
    #expect(try Data(contentsOf: file) == Data("replacement".utf8))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
}
@Test func selectedDirectoryRevalidatesDescendantsNotOnlyDirectoryTimestamp() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("folder/nested/selected")
    let snapshot = try await f.scan(); let service = f.service()
    let folder = f.input.appendingPathComponent("folder")
    let review = try await service.review(snapshot: snapshot, paths: [folder.path])
    try Data("changed descendant".utf8).write(to: file)
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .notAttempted)
    #expect(FileManager.default.fileExists(atPath: file.path))
}
@Test func backendFailureReportsPartialOutcomeWithoutAssumingCapacityGain() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let a = try f.write("a"), b = try f.write("b")
    let snapshot = try await f.scan()
    let service = f.service(FixtureTrashBackend(destination: f.output, failNames: ["b"]))
    let review = try await service.review(snapshot: snapshot, paths: [a.path, b.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.map(\.status) == [.trashed, .failed])
    #expect(result.items[1].message.contains("Could not move this item"))
    #expect(result.requiresRescan)
    #expect(FileManager.default.fileExists(atPath: b.path))
}
@Test func missingMoveDestinationStopsRemainingActionsAsUnknown() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let a = try f.write("a"), b = try f.write("b")
    let snapshot = try await f.scan()
    let service = f.service(FixtureTrashBackend(destination: f.output, missingDestination: true))
    let review = try await service.review(snapshot: snapshot, paths: [a.path, b.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.map(\.status) == [.unknown, .notAttempted])
    #expect(result.requiresRescan && result.snapshotInvalidationPersisted)
    #expect(FileManager.default.fileExists(atPath: b.path))
}
@Test func coordinatedValidationRejectsAChangeAfterInitialExecutionCheck() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected")
    let snapshot = try await f.scan()
    let service = f.service(f.bound(TrashMoveHooks(afterValidation: { try Data("changed at boundary".utf8).write(to: file) })))
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    // Refused by the final in-parent identity check: nothing moved (input 02 reported unknown).
    #expect(result.items.first?.status == .notAttempted)
    #expect(result.items.first?.message.contains("Nothing was moved") == true)
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
    #expect(try Data(contentsOf: file) == Data("changed at boundary".utf8))
}
@Test func invalidationPersistenceFailureStillRequiresRescanAndReportsIt() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected")
    let snapshot = try await f.scan(); let state = f.state
    let backend = FixtureTrashBackend(destination: f.output, afterMove: {
        let lock = state.appendingPathComponent("snapshots.json.lock")
        try FileManager.default.removeItem(at: lock)
        try FileManager.default.createDirectory(at: lock, withIntermediateDirectories: false)
    })
    let service = f.service(backend)
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .trashed)
    #expect(result.requiresRescan && !result.snapshotInvalidationPersisted)
    #expect(result.persistenceError != nil)
}

@Test func canonicalAncestorAliasScanPersistsIdentityAndMovesTheBoundObject() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected")
    let alias = f.root.appendingPathComponent("input-alias-parent")
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: f.root)
    // Only an ancestor alias is resolved; a symlink selected as the leaf remains rejected.
    let inputThroughAlias = alias.appendingPathComponent("input")
    let snapshot = try await InventoryStore(directory: f.state).scan(root: inputThroughAlias)
    #expect(snapshot.root == f.input.path)
    #expect(snapshot.rootIdentity != nil && snapshot.rootAncestors?.last?.path == snapshot.root)
    let reviewedInode = try inode(file)
    let service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let aliasResult = try await service.execute(reviewID: review.id)
    #expect(aliasResult.items.first?.status == .trashed)
    #expect(try inode(try #require(aliasResult.items.first?.trashURL)) == reviewedInode)
    do { _ = try await InventoryStore(directory: f.state).scan(root: alias); Issue.record("symlink leaf root was followed") } catch CoreError.invalidRoot { }
}
@Test func oldSnapshotsStayInvalidAfterTrashFreshScanAndStoreReopen() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let first = try f.write("first"), keep = try f.write("keep")
    let old = try await f.scan(), current = try await f.scan()
    let service = f.service()
    let review = try await service.review(snapshot: current, paths: [first.path])
    _ = try await service.execute(reviewID: review.id)
    let invalid = try await InventoryStore(directory: f.state).snapshots()
    let sameRoot = invalid.filter { $0.root == current.root }
    #expect(sameRoot.allSatisfy { $0.isStale })
    let fresh = try await f.scan()
    let reopened = try await InventoryStore(directory: f.state).snapshots()
    #expect(reopened.first { $0.id == fresh.id }?.isStale == false)
    #expect(reopened.first { $0.id == old.id }?.isStale == true)
    #expect(reopened.first { $0.id == current.id }?.isStale == true)
    do { _ = try await f.service().review(snapshot: old, paths: [keep.path]); Issue.record("old observation became actionable after a fresh scan") } catch ManualTrashError.requiresRescan { }
    let freshReview = try await f.service().review(snapshot: fresh, paths: [keep.path])
    #expect(freshReview.items.count == 1)
}
@Test func rescanMarkerPersistenceFailureAbortsBeforeAnyMove() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected")
    let snapshot = try await f.scan(), service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: f.state.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: f.state.path) }
    do { _ = try await service.execute(reviewID: review.id); Issue.record("move was permitted without durable marker") } catch { }
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: f.output.path).isEmpty)
    do { _ = try await service.execute(reviewID: review.id); Issue.record("failed dispatch left reusable review") } catch ManualTrashError.reviewUnavailable { }
}
@Test func changedSavedSnapshotRevisionRejectsPreviouslyReviewedToken() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected")
    let snapshot = try await f.scan(), service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    try DiskFile(directory: f.state, name: "snapshots.json", fallback: SnapshotLedger()).locked { ledger in
        let original = try #require(ledger.snapshots.first)
        ledger.snapshots[0] = InventorySnapshot(id: original.id, root: original.root, createdAt: original.createdAt, entries: original.entries, errors: ["revision changed"], capacity: original.capacity, scannerVersion: original.scannerVersion, volumeUUID: original.volumeUUID, rootDevice: original.rootDevice, rootInode: original.rootInode, rootIdentity: original.rootIdentity, rootAncestors: original.rootAncestors)
    }
    do { _ = try await service.execute(reviewID: review.id); Issue.record("review ignored a saved revision change") } catch ManualTrashError.reviewUnavailable { }
    #expect(FileManager.default.fileExists(atPath: file.path))
}
private final class BlockingFailedFixtureBackend: TrashBackend, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var attempts = 0
    func awaitEntered() -> Bool { entered.wait(timeout: .now() + 3) == .success }
    var count: Int { lock.lock(); defer { lock.unlock() }; return attempts }
    func moveToTrash(_ target: TrashTarget, validate: () throws -> Void) throws -> URL {
        try validate()
        lock.lock(); attempts += 1; lock.unlock()
        entered.signal()
        guard release.wait(timeout: .now() + 5) == .success else { throw CocoaError(.userCancelled) }
        throw CocoaError(.fileWriteNoPermission)
    }
}
@Test func duplicateExecuteCannotReuseReviewDuringAnIntactBackendFailure() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected"), backend = BlockingFailedFixtureBackend()
    let snapshot = try await f.scan()
    let service = ManualTrashService(directory: f.state, backend: backend)
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let first = Task { try await service.execute(reviewID: review.id) }
    defer { backend.release.signal() }
    let entered = await Task.detached { backend.awaitEntered() }.value
    try #require(entered)
    do { _ = try await service.execute(reviewID: review.id); Issue.record("duplicate token accepted while suspended") } catch ManualTrashError.reviewUnavailable { }
    backend.release.signal()
    let result = try await first.value
    #expect(result.items.first?.status == .failed && result.requiresRescan)
    #expect(backend.count == 1)
}

// MARK: Core input 03 – bound move (finding 1)

@Test func leafSwapInsidePinnedParentBeforeFinalCheckIsRefused() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("folder/selected"), parked = f.root.appendingPathComponent("parked-original")
    let snapshot = try await f.scan()
    let service = f.service(f.bound(TrashMoveHooks(afterParentOpened: {
        try FileManager.default.moveItem(at: file, to: parked)
        try Data("replacement".utf8).write(to: file)
    })))
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .notAttempted)
    #expect(result.items.first?.message.contains("no longer held the reviewed item") == true)
    #expect(try Data(contentsOf: file) == Data("replacement".utf8))
    #expect(try Data(contentsOf: parked) == Data("fixture".utf8))
    #expect(try f.trashNames().isEmpty)
}
@Test func leafSwapAtTheRenameInstantIsReportedUnknownLeftInTrashAndStopsTheBatch() async throws {
    for symlink in [false, true] {
        let f = try TrashFixture(); defer { f.clean() }
        let file = try f.write("selected"), second = try f.write("z-second")
        let parked = f.root.appendingPathComponent("parked-original")
        let outside = f.root.appendingPathComponent("outside"); try Data("outside".utf8).write(to: outside)
        let snapshot = try await f.scan()
        // Swap after the final fstatat and before renameatx_np: the accepted residual window.
        let service = f.service(f.bound(TrashMoveHooks(beforeRename: {
            guard !FileManager.default.fileExists(atPath: parked.path) else { return }
            try FileManager.default.moveItem(at: file, to: parked)
            if symlink { try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside) }
            else { try Data("replacement".utf8).write(to: file) }
        })))
        let review = try await service.review(snapshot: snapshot, paths: [file.path, second.path])
        let result = try await service.execute(reviewID: review.id)
        #expect(result.items.map(\.status) == [.unknown, .notAttempted])
        let item = try #require(result.items.first)
        let destination = try #require(item.trashURL)
        #expect(item.message.contains("last known destination in Trash was \(destination.path); it may no longer be there"))
        #expect(!item.message.contains("left in Trash at"))
        #expect(!item.message.contains("put back"))
        #expect(result.requiresRescan)
        // The unexpected entry stays in Trash; nothing moves it back.
        #expect(try f.trashNames() == ["selected"])
        #expect((try? FileManager.default.attributesOfItem(atPath: file.path)) == nil)
        if symlink { #expect(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path) == outside.path) }
        else { #expect(try Data(contentsOf: destination) == Data("replacement".utf8)) }
        #expect(try Data(contentsOf: outside) == Data("outside".utf8))
        #expect(try Data(contentsOf: parked) == Data("fixture".utf8))
        #expect(FileManager.default.fileExists(atPath: second.path))
    }
}
@Test func symlinkLeafAtTheFinalCheckIsRefused() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected"), outside = f.root.appendingPathComponent("outside")
    try Data("outside".utf8).write(to: outside)
    let snapshot = try await f.scan()
    let service = f.service(f.bound(TrashMoveHooks(afterParentOpened: {
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: outside)
    })))
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .notAttempted)
    #expect(try Data(contentsOf: outside) == Data("outside".utf8))
    #expect(try f.trashNames().isEmpty)
}
@Test func ancestorSwapBeforeTheParentIsPinnedIsRefused() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("folder/selected"), folder = f.input.appendingPathComponent("folder")
    let renamed = f.input.appendingPathComponent("original-folder")
    let snapshot = try await f.scan()
    let service = f.service(f.bound(TrashMoveHooks(afterValidation: {
        try FileManager.default.moveItem(at: folder, to: renamed)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: file)
    })))
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .notAttempted)
    #expect(try Data(contentsOf: file) == Data("replacement".utf8))
    #expect(try Data(contentsOf: renamed.appendingPathComponent("selected")) == Data("fixture".utf8))
    #expect(try f.trashNames().isEmpty)
}
@Test func ancestorSwapAfterTheParentIsPinnedStillMovesOnlyTheReviewedObject() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("folder/selected"), folder = f.input.appendingPathComponent("folder")
    let reviewedInode = try inode(file)
    let snapshot = try await f.scan()
    let service = f.service(f.bound(TrashMoveHooks(afterParentOpened: {
        try FileManager.default.moveItem(at: folder, to: f.input.appendingPathComponent("original-folder"))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try Data("replacement".utf8).write(to: file)
    })))
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    // The pinned parent descriptor cannot be redirected: the reviewed object moved,
    // the replacement stayed. The changed scope is reported, not called a success.
    let item = try #require(result.items.first)
    #expect(item.status == .unknown)
    #expect(try inode(try #require(item.trashURL)) == reviewedInode)
    #expect(try Data(contentsOf: file) == Data("replacement".utf8))
    #expect(try f.trashNames() == ["selected"])
}
@Test func crossVolumeTrashFolderIsRefusedWithoutMoving() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("selected")
    // /dev is devfs: a different device, opened read-only and only fstat-ed.
    let other = URL(fileURLWithPath: "/dev")
    try #require(try FileIdentityReader.at(other.path).device != FileIdentityReader.at(file.path).device)
    let snapshot = try await f.scan()
    let service = f.service(SystemTrashBackend(trashDirectory: other))
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .notAttempted)
    #expect(result.items.first?.message.contains("same volume as your Trash") == true)
    #expect(try Data(contentsOf: file) == Data("fixture".utf8))
}
@Test func trashNameCollisionNeverReplacesAnExistingTrashEntry() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let file = try f.write("report.txt", "selected")
    try Data("already in trash".utf8).write(to: f.output.appendingPathComponent("report.txt"))
    let snapshot = try await f.scan(), service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    let destination = try #require(result.items.first?.trashURL)
    #expect(result.items.first?.status == .trashed)
    #expect(destination.lastPathComponent != "report.txt" && destination.pathExtension == "txt")
    #expect(try Data(contentsOf: destination) == Data("selected".utf8))
    #expect(try Data(contentsOf: f.output.appendingPathComponent("report.txt")) == Data("already in trash".utf8))
}
@Test func selectedDirectoryMovesAsOneBoundObject() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    _ = try f.write("folder/nested/a"); _ = try f.write("folder/b")
    let folder = f.input.appendingPathComponent("folder"), reviewedInode = try inode(folder)
    let snapshot = try await f.scan(), service = f.service()
    let review = try await service.review(snapshot: snapshot, paths: [folder.path])
    let result = try await service.execute(reviewID: review.id)
    let destination = try #require(result.items.first?.trashURL)
    #expect(result.items.first?.status == .trashed)
    #expect(try inode(destination) == reviewedInode)
    #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("nested/a").path))
    #expect(!FileManager.default.fileExists(atPath: folder.path))
}

// MARK: Core input 03 – overlapping-root invalidation (finding 2)

@Test func moveInvalidatesEveryOverlappingRootAndKeepsDisjointRootsValid() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let moved = try f.write("a/file"), other = try f.write("a/other/keep"), sub = try f.write("a/sub/keep")
    let disjoint = try f.write("b/keep"), ancestorKeep = try f.write("top-keep")
    let a = f.input.appendingPathComponent("a")
    let ancestor = try await f.scan()                                   // input: ancestor of reviewed root
    let equal = try await f.scan(a)                                     // a: equal root, older observation
    let descendant = try await f.scan(a.appendingPathComponent("other")) // a/other: below reviewed root, not containing the moved path
    let deeper = try await f.scan(a.appendingPathComponent("sub"))       // a/sub: below reviewed root
    let sibling = try await f.scan(f.input.appendingPathComponent("b"))  // b: disjoint
    let reviewed = try await f.scan(a)
    let service = f.service()
    let review = try await service.review(snapshot: reviewed, paths: [moved.path])
    let result = try await service.execute(reviewID: review.id)
    #expect(result.items.first?.status == .trashed && result.snapshotInvalidationPersisted)
    let saved = try await InventoryStore(directory: f.state).snapshots()
    for stale in [ancestor, equal, descendant, deeper, reviewed] {
        let isStale = saved.first { $0.id == stale.id }?.isStale
        #expect(isStale == true, "\(stale.root) should be stale")
    }
    let siblingStale = saved.first { $0.id == sibling.id }?.isStale
    #expect(siblingStale == false)
    for (snapshot, path) in [(ancestor, ancestorKeep), (descendant, other), (deeper, sub), (equal, other)] {
        do { _ = try await f.service().review(snapshot: snapshot, paths: [path.path]); Issue.record("overlapping old scan stayed actionable: \(snapshot.root)") }
        catch ManualTrashError.requiresRescan { }
    }
    let siblingReview = try await f.service().review(snapshot: sibling, paths: [disjoint.path])
    #expect(siblingReview.items.map(\.path) == [disjoint.path])
}
@Test func affectedRootsCoverAncestorDescendantEqualButNotDisjoint() {
    let roots = ["/x", "/x/a", "/x/a/other", "/x/a-b", "/x/b", "/y"]
    let affected = ManualTrashService.affectedRoots(savedRoots: roots, reviewedRoot: "/x/a", paths: ["/x/a/file"])
    #expect(affected == ["/x", "/x/a", "/x/a/other"])
}

// MARK: Real user Trash smoke (one generated file; opt-in)

@Test(.enabled(if: ProcessInfo.processInfo.environment["DISK_CLEANER_RUN_REAL_TRASH_SMOKE"] == "1",
               "Opt-in: set DISK_CLEANER_RUN_REAL_TRASH_SMOKE=1 to move one generated file into the real Trash"))
func realUserTrashSmokeMovesOneGeneratedFile() async throws {
    let f = try TrashFixture(); defer { f.clean() }
    let name = "disk-cleaner-core04-smoke-\(UUID().uuidString).txt"
    let file = try f.write(name, "generated by DiskCleanerCoreTests; safe to delete"), reviewedInode = try inode(file)
    let snapshot = try await f.scan()
    let service = ManualTrashService(directory: f.state, backend: SystemTrashBackend())
    let review = try await service.review(snapshot: snapshot, paths: [file.path])
    let result = try await service.execute(reviewID: review.id)
    let item = try #require(result.items.first)
    #expect(item.status == .trashed, "\(item.message)")
    let destination = try #require(item.trashURL)
    let userTrash = try FileIdentityReader.canonicalDirectoryPath(FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false).path)
    #expect(destination.deletingLastPathComponent().path == userTrash)
    #expect(try inode(destination) == reviewedInode)
    #expect(!FileManager.default.fileExists(atPath: file.path))
    // Deliberately left in Trash: deleting by path after a check is not atomic.
    print("REAL_TRASH_SMOKE ran: left in Trash for manual cleanup: \(destination.path)")
}
