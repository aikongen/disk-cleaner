import Foundation
import DiskCleanerCore

// The UI talks to Trash only through this flow. Two implementations exist:
// FixtureTrashFlow (preview: marks items in memory, never touches the disk) and
// LiveTrashFlow (normal app: Core review, then the real move only on confirm).

struct TrashReviewModel: Sendable, Identifiable, Equatable {
    struct Item: Sendable, Identifiable, Equatable {
        var id: String { path }
        let path: String
        let name: String
        let bytes: Int64
        let isDirectory: Bool
    }
    let id: UUID
    let snapshotID: UUID
    let root: String
    let items: [Item]
    let warning: String
    var totalBytes: Int64 { items.reduce(0) { $0 + $1.bytes } }
}

enum TrashOutcomeStatus: String, Sendable, Equatable {
    case moved, notMoved, notAttempted, unknown
    var title: String {
        switch self {
        case .moved: "Moved to Trash"
        case .notMoved: "Not moved"
        case .notAttempted: "Not attempted"
        case .unknown: "Outcome unknown"
        }
    }
}

struct TrashOutcomeModel: Sendable, Equatable {
    struct Item: Sendable, Identifiable, Equatable {
        var id: String { path }
        let path: String
        let name: String
        let status: TrashOutcomeStatus
        let message: String
        /// Last known destination in Trash; it may no longer be there.
        var trashPath: String? = nil
    }
    let items: [Item]
    let requiresRescan: Bool
    let invalidationPersisted: Bool
    let persistenceError: String?
    var movedCount: Int { items.filter { $0.status == .moved }.count }
}

protocol TrashFlow: Sendable {
    /// True when the flow only marks example items.
    var isExample: Bool { get }
    /// When set, the final confirmation is disabled with this one-line reason.
    var confirmHeldReason: String? { get }
    func review(snapshot: InventorySnapshot, paths: [String]) async throws -> TrashReviewModel
    func execute(reviewID: UUID) async throws -> TrashOutcomeModel
    func discard(reviewID: UUID) async
}

enum FixtureTrashError: Error, LocalizedError, Equatable {
    case emptySelection, rootSelection, overlappingSelection, notInScan(String), reviewUnavailable
    var errorDescription: String? {
        switch self {
        case .emptySelection: "Select at least one file or folder."
        case .rootSelection: "The scanned root itself cannot be moved to Trash."
        case .overlappingSelection: "Select a folder or its contents, not both."
        case .notInScan(let path): "This selection is outside the saved scan: \(path)"
        case .reviewUnavailable: "This review is no longer available. Review the selection again."
        }
    }
}

/// Preview-only Trash. It validates the selection against the saved example
/// snapshot and records outcomes in memory. It has no FileManager, file
/// coordinator or Core backend, so it cannot move, rename or delete anything.
final class FixtureTrashFlow: TrashFlow, @unchecked Sendable {
    let isExample = true
    let confirmHeldReason: String? = nil
    /// Example items reported as changed since the scan, to show a partial outcome.
    let changedSinceScan: Set<String>
    private let lock = NSLock()
    private var pending: (review: TrashReviewModel, snapshot: InventorySnapshot)?
    private var marked: Set<String> = []

    init(changedSinceScan: Set<String> = []) { self.changedSinceScan = changedSinceScan }

    var markedPaths: Set<String> { lock.withLock { marked } }

    func review(snapshot: InventorySnapshot, paths: [String]) async throws -> TrashReviewModel { try reviewNow(snapshot: snapshot, paths: paths) }
    func execute(reviewID: UUID) async throws -> TrashOutcomeModel { try executeNow(reviewID: reviewID) }
    func discard(reviewID: UUID) async { discardNow(reviewID: reviewID) }

    func reviewNow(snapshot: InventorySnapshot, paths: [String]) throws -> TrashReviewModel {
        let unique = Array(Set(paths)).sorted()
        guard !unique.isEmpty else { throw FixtureTrashError.emptySelection }
        let byPath = Dictionary(snapshot.entries.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var items: [TrashReviewModel.Item] = []
        for path in unique {
            if path == snapshot.root { throw FixtureTrashError.rootSelection }
            guard let entry = byPath[path] else { throw FixtureTrashError.notInScan(path) }
            if unique.contains(where: { $0 != path && path.hasPrefix($0 + "/") }) { throw FixtureTrashError.overlappingSelection }
            items.append(.init(path: entry.path, name: entry.name, bytes: entry.apparentBytes, isDirectory: entry.isDirectory))
        }
        let review = TrashReviewModel(id: UUID(), snapshotID: snapshot.id, root: snapshot.root, items: items,
                                      warning: "Only these selected items would be moved to Trash. Trash does not immediately free disk space. Example data: nothing on disk is moved.")
        lock.withLock { pending = (review, snapshot) }
        return review
    }

    func executeNow(reviewID: UUID) throws -> TrashOutcomeModel {
        // Single use, like Core: the review is consumed before any outcome is produced.
        let prepared: (review: TrashReviewModel, snapshot: InventorySnapshot)? = lock.withLock {
            guard let current = pending, current.review.id == reviewID else { return nil }
            pending = nil
            return current
        }
        guard let prepared else { throw FixtureTrashError.reviewUnavailable }
        let items = prepared.review.items.map { item -> TrashOutcomeModel.Item in
            if changedSinceScan.contains(item.path) {
                return .init(path: item.path, name: item.name, status: .notMoved, message: "This item or an ancestor changed. Scan again before moving it to Trash.")
            }
            return .init(path: item.path, name: item.name, status: .moved, message: "Marked as moved in this example. Nothing on disk was touched.")
        }
        lock.withLock { for item in items where item.status == .moved { marked.insert(item.path) } }
        return TrashOutcomeModel(items: items, requiresRescan: true, invalidationPersisted: true, persistenceError: nil)
    }

    func discardNow(reviewID: UUID) { lock.withLock { if pending?.review.id == reviewID { pending = nil } } }
}

/// Normal app only. ManualTrashService needs a backend when it is created, but no
/// real backend exists until the user presses Move to Trash on the review screen.
/// Until then every move is refused without validating or touching a path.
final class ConfirmGatedTrashBackend: TrashBackend, @unchecked Sendable {
    struct NotConfirmed: Error, LocalizedError { var errorDescription: String? { "Move to Trash was not confirmed. Nothing was moved." } }
    private let lock = NSLock()
    private var armed: (any TrashBackend)?
    func arm(_ backend: any TrashBackend) { lock.withLock { armed = backend } }
    func disarm() { lock.withLock { armed = nil } }
    var isArmed: Bool { lock.withLock { armed != nil } }
    func moveToTrash(_ target: TrashTarget, validate: () throws -> Void) throws -> URL {
        guard let backend = lock.withLock({ armed }) else { throw NotConfirmed() }
        return try backend.moveToTrash(target, validate: validate)
    }
}

/// Normal app: exact-path review and the move run through Core's ManualTrashService.
/// SystemTrashBackend is constructed in exactly one place, `execute`, which the UI
/// calls only from the Move to Trash button on the review screen. The fixture
/// preview uses FixtureTrashFlow and can never reach this type.
final class LiveTrashFlow: TrashFlow {
    let isExample = false
    let confirmHeldReason: String? = nil
    private let service: ManualTrashService
    private let gate = ConfirmGatedTrashBackend()
    private let makeConfirmedBackend: @Sendable () -> any TrashBackend

    /// The only construction site of SystemTrashBackend in the app.
    @Sendable static func makeSystemBackend() -> any TrashBackend { SystemTrashBackend() }

    /// - makeConfirmedBackend: tests inject a recording fixture backend; the app uses the default.
    init(directory: URL, makeConfirmedBackend: @escaping @Sendable () -> any TrashBackend = LiveTrashFlow.makeSystemBackend) {
        self.makeConfirmedBackend = makeConfirmedBackend
        service = ManualTrashService(directory: directory, backend: gate)
    }

    var isArmed: Bool { gate.isArmed }

    func review(snapshot: InventorySnapshot, paths: [String]) async throws -> TrashReviewModel {
        let review = try await service.review(snapshot: snapshot, paths: paths)
        return TrashReviewModel(id: review.id, snapshotID: review.snapshotID, root: review.root,
                                items: review.items.map { .init(path: $0.path, name: $0.name, bytes: $0.bytes, isDirectory: $0.isDirectory) },
                                warning: review.warning)
    }

    /// Called only by the confirm action. The real backend exists only for this call.
    func execute(reviewID: UUID) async throws -> TrashOutcomeModel {
        gate.arm(makeConfirmedBackend())
        defer { gate.disarm() }
        return Self.outcome(try await service.execute(reviewID: reviewID))
    }

    func discard(reviewID: UUID) async { await service.discardReview(id: reviewID) }

    static func outcome(_ result: TrashBatchResult) -> TrashOutcomeModel {
        TrashOutcomeModel(items: result.items.map { item in
            let status: TrashOutcomeStatus = switch item.status {
            case .trashed: .moved
            case .failed: .notMoved
            case .notAttempted: .notAttempted
            case .unknown: .unknown
            }
            return .init(path: item.path, name: URL(fileURLWithPath: item.path).lastPathComponent, status: status, message: item.message, trashPath: item.trashURL?.path)
        }, requiresRescan: result.requiresRescan, invalidationPersisted: result.snapshotInvalidationPersisted, persistenceError: result.persistenceError)
    }
}
