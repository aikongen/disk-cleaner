import Foundation
import Testing
@testable import DiskCleanerCore

private func scannerFixture() throws -> URL {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-scanner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    return URL(fileURLWithPath: try FileIdentityReader.canonicalDirectoryPath(path.path))
}

@Test func scannerReportsOmittedLinksAndUnknownHardLinkAllocation() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let fm = FileManager.default
    let root = fixture.appendingPathComponent("input")
    let folder = root.appendingPathComponent("folder")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let file = folder.appendingPathComponent("file")
    try Data(repeating: 7, count: 8192).write(to: file)
    try fm.linkItem(at: file, to: folder.appendingPathComponent("hardlink"))
    try fm.createSymbolicLink(at: folder.appendingPathComponent("link"), withDestinationURL: fixture)
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    let result = try await store.scan(root: root)
    let links = result.entries.filter { $0.name == "file" || $0.name == "hardlink" }
    #expect(links.count == 2)
    #expect(links.allSatisfy { $0.apparentBytes == 8192 && $0.allocatedBytes == nil && $0.coverage == .partial })
    #expect(!result.entries.contains { $0.name == "link" })
    #expect(result.errors.contains { $0.contains("symbolic link omitted") })
    #expect(result.entries.first { $0.name == "folder" }?.coverage == .partial)
    #expect(compareSnapshots(result, result).isEmpty)
}

@Test func scannerLimitCountsOmissions() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let fm = FileManager.default
    let root = fixture.appendingPathComponent("input")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    for index in 0..<5 { try fm.createSymbolicLink(at: root.appendingPathComponent("link\(index)"), withDestinationURL: fixture) }
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    let result = try await store.scan(root: root, entryLimit: 2, onDirectoryObserved: nil)
    #expect(result.errors.filter { $0.contains("symbolic link omitted") }.count == 2)
    #expect(result.errors.contains { $0.contains("Observation limit") })
    #expect(result.entries.isEmpty)
}

@Test func scannerDoesNotTraverseSwappedDirectory() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let fm = FileManager.default
    let root = fixture.appendingPathComponent("input")
    let victim = root.appendingPathComponent("victim")
    let outside = fixture.appendingPathComponent("outside")
    let displaced = fixture.appendingPathComponent("displaced")
    try fm.createDirectory(at: victim, withIntermediateDirectories: true)
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data([42]).write(to: outside.appendingPathComponent("outside-marker"))
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    let result = try await store.scan(root: root, entryLimit: 100) { path in
        guard path.lastPathComponent == "victim" else { return }
        try? FileManager.default.moveItem(at: path, to: displaced)
        try? FileManager.default.createSymbolicLink(at: path, withDestinationURL: outside)
    }
    #expect(!result.entries.contains { $0.name == "outside-marker" })
    #expect(result.entries.first { $0.name == "victim" }?.coverage == .partial)
    #expect(result.errors.contains { $0.contains("victim") })
}

@Test func scannerReportsSparseFileWithoutClaimingReclaimableSpace() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let fm = FileManager.default
    let root = fixture.appendingPathComponent("input")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    let file = root.appendingPathComponent("sparse")
    try Data().write(to: file)
    let handle = try FileHandle(forWritingTo: file)
    try handle.truncate(atOffset: 8_388_608)
    try handle.close()
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    let result = try await store.scan(root: root)
    let entry = try #require(result.entries.first { $0.name == "sparse" })
    #expect(entry.apparentBytes == 8_388_608)
    #expect(entry.allocatedBytes != nil)
    #expect(entry.allocatedBytes! >= 0)
}

@Test func cancelledTraversalDoesNotPersistObservation() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let root = fixture.appendingPathComponent("input")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("nested"), withIntermediateDirectories: true)
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    do {
        _ = try await store.scan(root: root, entryLimit: 100) { _ in
            withUnsafeCurrentTask { $0?.cancel() }
        }
        Issue.record("Cancelled traversal returned a snapshot")
    } catch is CancellationError { }
    #expect(try await store.snapshots().isEmpty)
}

@Test func omissionDoesNotSuppressUnrelatedCompleteSiblingComparison() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let fm = FileManager.default
    let root = fixture.appendingPathComponent("input")
    let incomplete = root.appendingPathComponent("incomplete")
    let complete = root.appendingPathComponent("complete")
    try fm.createDirectory(at: incomplete, withIntermediateDirectories: true)
    try fm.createDirectory(at: complete, withIntermediateDirectories: true)
    try fm.createSymbolicLink(at: incomplete.appendingPathComponent("link"), withDestinationURL: fixture)
    let file = complete.appendingPathComponent("file")
    try Data(repeating: 1, count: 10).write(to: file)
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    let before = try await store.scan(root: root)
    try Data(repeating: 2, count: 20).write(to: file)
    let after = try await store.scan(root: root)
    #expect(after.entries.first { $0.name == "incomplete" }?.coverage == .partial)
    #expect(after.entries.first { $0.name == "complete" }?.coverage == .complete)
    if after.volumeUUID != nil && before.volumeUUID != nil {
        let changes = compareSnapshots(before, after)
        #expect(changes.first { $0.path == complete.path }?.changeBytes == 10)
        #expect(!changes.contains { $0.path == incomplete.path })
    } else {
        #expect(compareSnapshots(before, after).isEmpty)
        #expect(after.errors.contains { $0.contains("Volume identity unavailable") })
    }
}

@Test func rootReplacementAndDifferentVolumeAreNotComparable() async throws {
    let fixture = try scannerFixture(); defer { try? FileManager.default.removeItem(at: fixture) }
    let fm = FileManager.default
    let root = fixture.appendingPathComponent("input")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([1]).write(to: root.appendingPathComponent("file"))
    let store = InventoryStore(directory: fixture.appendingPathComponent("state"))
    let before = try await store.scan(root: root)
    try fm.moveItem(at: root, to: fixture.appendingPathComponent("old-input"))
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    try Data([1, 2]).write(to: root.appendingPathComponent("file"))
    let after = try await store.scan(root: root)
    #expect(before.rootInode != after.rootInode)
    #expect(compareSnapshots(before, after).isEmpty)
    let item = InventoryEntry(path: "/fixture/file", name: "file", apparentBytes: 1, allocatedBytes: 1, modifiedAt: nil, isDirectory: false, coverage: .complete)
    let first = InventorySnapshot(root: "/fixture", entries: [item], errors: [], capacity: nil, scannerVersion: 2, volumeUUID: "volume-A", rootDevice: 1, rootInode: 2)
    let second = InventorySnapshot(root: "/fixture", entries: [item], errors: [], capacity: nil, scannerVersion: 2, volumeUUID: "volume-B", rootDevice: 1, rootInode: 2)
    #expect(compareSnapshots(first, second).isEmpty)
}

@Test func legacySnapshotDecodesButIsNotComparable() throws {
    let item = InventoryEntry(path: "/fixture/file", name: "file", apparentBytes: 1, allocatedBytes: 1, modifiedAt: nil, isDirectory: false, coverage: .complete)
    let old = InventorySnapshot(root: "/fixture", entries: [item], errors: [], capacity: nil)
    let encoded = try JSONEncoder().encode(old)
    let decoded = try JSONDecoder().decode(InventorySnapshot.self, from: encoded)
    #expect(decoded.entries.count == 1)
    #expect(decoded.scannerVersion == nil)
    let current = InventorySnapshot(root: "/fixture", entries: [item], errors: [], capacity: nil, scannerVersion: 2, volumeUUID: "volume-A", rootDevice: 1, rootInode: 2)
    #expect(compareSnapshots(decoded, current).isEmpty)
}
