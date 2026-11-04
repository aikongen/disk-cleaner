import Foundation
import Testing
@testable import DiskCleanerCore

private func navEntry(_ path: String, bytes: Int64 = 0, directory: Bool = false, modified: Date? = nil, coverage: Coverage = .complete) -> InventoryEntry {
    InventoryEntry(path: path, name: URL(fileURLWithPath: path).lastPathComponent, apparentBytes: bytes, allocatedBytes: nil, modifiedAt: modified, isDirectory: directory, coverage: coverage)
}
@Test func savedInventoryNavigationSearchSortAndScopeNeverNeedFilesystem() throws {
    let date = Date(timeIntervalSince1970: 100)
    let snapshot = InventorySnapshot(root: "/recorded", entries: [navEntry("/recorded/Documents", directory: true, coverage: .partial), navEntry("/recorded/Documents/a.txt", bytes: 4, modified: date), navEntry("/recorded/Documents/z.txt", bytes: 8), navEntry("/recorded/archive", bytes: 2)], errors: ["A gap remains unknown"], capacity: nil)
    let browser = try InventoryBrowser(snapshot: snapshot)
    #expect(try browser.children(of: "/recorded").map(\.name) == ["archive", "Documents"])
    #expect(try browser.breadcrumbs(to: "/recorded/Documents").map(\.path) == ["/recorded", "/recorded/Documents"])
    #expect(browser.parent(of: "/recorded/Documents") == "/recorded")
    #expect(browser.parent(of: "/recorded") == nil)
    #expect(try browser.children(of: "/recorded/Documents", sort: .name, direction: .ascending).map(\.name) == ["a.txt", "z.txt"])
    #expect(try browser.children(of: "/recorded/Documents", sort: .modified, direction: .descending).map(\.name) == ["a.txt", "z.txt"])
    #expect(try browser.children(of: "/recorded", search: "a.txt", recursive: true).map(\.path) == ["/recorded/Documents/a.txt"])
    #expect(try browser.children(of: "/recorded/Documents", search: "archive", recursive: true).isEmpty)
    #expect(browser.entry(at: "/recorded/Documents")?.coverage == .partial)
    #expect(browser.entry(at: "/recorded/Documents")?.allocatedBytes == nil)
    #expect(try browser.summary(of: "/recorded").allocatedBytes == nil)
    #expect(try browser.summary(of: "/recorded").hasCoverageGaps)
    do { _ = try browser.children(of: "/recorded-other"); Issue.record("prefix escape accepted") } catch InventoryNavigationError.outsideScope { }
    do { _ = try browser.children(of: "/recorded/Documents/../.."); Issue.record("noncanonical escape accepted") } catch InventoryNavigationError.outsideScope { }
}
@Test func malformedSavedTreeIsRejectedRatherThanInventingNavigation() throws {
    let orphan = InventorySnapshot(root: "/recorded", entries: [navEntry("/recorded/missing/file")], errors: [], capacity: nil)
    #expect(throws: InventoryNavigationError.self) { try InventoryBrowser(snapshot: orphan) }
    let duplicate = InventorySnapshot(root: "/recorded", entries: [navEntry("/recorded/file"), navEntry("/recorded/file")], errors: [], capacity: nil)
    #expect(throws: InventoryNavigationError.self) { try InventoryBrowser(snapshot: duplicate) }
}
private func functionalDirectory() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-functional-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return URL(fileURLWithPath: try FileIdentityReader.canonicalDirectoryPath(root.path))
}
@Test func firstLaunchAppearanceSeedAndExplicitSavedChoiceRemainSeparate() async throws {
    let root = try functionalDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let store = PreferencesStore(directory: root)
    #expect(try await store.load() == UserPreferences())
    #expect(SnapshotRetention.allCases.map(\.rawValue) == [5, 10, 30])
    #expect(try await store.load(defaults: UserPreferences(appearance: .purple)).appearance == .purple)
    #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("preferences.json").path))
    let chosen = UserPreferences(appearance: .green, rememberLastScan: false, retention: .five)
    try await store.save(chosen)
    #expect(try await PreferencesStore(directory: root).load(defaults: UserPreferences(appearance: .purple)) == chosen)
    let future = Data("{\"version\":99,\"preferences\":{\"appearance\":\"green\",\"rememberLastScan\":true,\"retention\":30}}".utf8)
    try future.write(to: root.appendingPathComponent("preferences.json"))
    do { try await store.save(chosen); Issue.record("unsupported settings overwritten") } catch PreferencesError.unsupportedVersion { }
    #expect(try Data(contentsOf: root.appendingPathComponent("preferences.json")) == future)
}
@Test func selectedRetentionPrunesOnlyStoredObservations() async throws {
    let root = try functionalDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("input"); let state = root.appendingPathComponent("state")
    try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    let file = input.appendingPathComponent("keep.txt"); try Data("keep".utf8).write(to: file)
    let store = InventoryStore(directory: state)
    for _ in 0..<7 { _ = try await store.scan(root: input) }
    #expect(try await store.snapshots().count == 7)
    try await store.applyRetention(.five)
    #expect(try await store.snapshots().count == 5)
    #expect(try Data(contentsOf: file) == Data("keep".utf8))
    _ = try await store.scan(root: input, retention: .five)
    #expect(try await store.snapshots().count == 5)
}
@Test func activeFileOperationExcludesScanForSameStoreButNotOtherFixtures() async throws {
    let root = try functionalDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("input"); try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
    let state = root.appendingPathComponent("state"); let gate = InventoryOperationGate()
    let signal = FunctionalGateSignal()
    let running = Task {
        try await gate.perform(key: state.standardizedFileURL.path) { await signal.hold() }
    }
    await signal.waitForEntry()
    do { _ = try await InventoryStore(directory: state, operationGate: gate).scan(root: input); Issue.record("scan overlapped active file action") } catch InventoryOperationError.busy { }
    _ = try await InventoryStore(directory: root.appendingPathComponent("other-state"), operationGate: gate).scan(root: input)
    await signal.release(); try await running.value
    _ = try await InventoryStore(directory: state, operationGate: gate).scan(root: input)
}
private actor FunctionalGateSignal {
    private var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    func hold() async { entered = true; await withCheckedContinuation { continuation = $0 } }
    func waitForEntry() async { while !entered { await Task.yield() } }
    func release() { continuation?.resume(); continuation = nil }
}

@Test func unknownSizesSortLastAndDoNotBecomeAllocatedZero() throws {
    let snapshot = InventorySnapshot(root: "/scope", entries: [navEntry("/scope/known", bytes: 4), navEntry("/scope/unknown", coverage: .unavailable)], errors: ["unknown size"], capacity: nil)
    let browser = try InventoryBrowser(snapshot: snapshot)
    #expect(try browser.children(of: "/scope", sort: .size, direction: .ascending).map(\.name) == ["known", "unknown"])
    #expect(try browser.children(of: "/scope", sort: .size, direction: .descending).map(\.name) == ["known", "unknown"])
    #expect(browser.entry(at: "/scope/unknown")?.knownApparentBytes == nil)
    let summary = try browser.summary(of: "/scope")
    #expect(summary.recordedApparentBytes == 4 && summary.allocatedBytes == nil && summary.hasCoverageGaps)
}
@Test func navigationAndCrossFolderSearchUseSavedObservationWithoutRescan() async throws {
    let root = try functionalDirectory(); defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("input"), state = root.appendingPathComponent("state")
    for path in ["a/needle", "b/needle"] {
        let file = input.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: file)
    }
    let store = InventoryStore(directory: state)
    let snapshot = try await store.scan(root: input)
    try Data("created later".utf8).write(to: input.appendingPathComponent("a/new-file"))
    let browser = try InventoryBrowser(snapshot: snapshot)
    #expect(try browser.children(of: input.path, search: "needle", recursive: true).count == 2)
    #expect(try browser.children(of: input.appendingPathComponent("a").path, search: "needle", recursive: true).count == 1)
    #expect(try browser.children(of: input.appendingPathComponent("a").path).map(\.name) == ["needle"])
    #expect(try await store.snapshots().map(\.id) == [snapshot.id])
}
