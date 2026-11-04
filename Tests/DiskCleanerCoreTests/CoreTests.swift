import Foundation
import Testing
@testable import DiskCleanerCore

private func temporary() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
@Test func persistedScansDoNotFollowSymlinks() async throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let input = root.appendingPathComponent("input"); let data = root.appendingPathComponent("data")
    try FileManager.default.createDirectory(at: input.appendingPathComponent("nested"), withIntermediateDirectories: true)
    try Data(repeating: 42, count: 128).write(to: input.appendingPathComponent("nested/file"))
    try FileManager.default.createSymbolicLink(at: input.appendingPathComponent("outside"), withDestinationURL: data)
    let store = InventoryStore(directory: data)
    let scan = try await store.scan(root: input)
    #expect(scan.entries.contains { $0.name == "file" && $0.apparentBytes == 128 })
    #expect(!scan.entries.contains { $0.name == "outside" })
    #expect(scan.entries.first { $0.name == "nested" }?.apparentBytes ?? 0 >= 128)
    let reopened = InventoryStore(directory: data)
    #expect(try await reopened.snapshots().first?.id == scan.id)
}
@Test func persistedJobsDeduplicateAndRejectConflictingTargets() async throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = JobStore(directory: root, capacityURL: root)
    let first = try await store.enqueue(targetBytes: 1, key: "request-1")
    let reopened = JobStore(directory: root, capacityURL: root)
    let retry = try await reopened.enqueue(targetBytes: 1, key: "request-1")
    #expect(first.id == retry.id)
    do { _ = try await reopened.enqueue(targetBytes: 2, key: "request-1"); Issue.record("Conflicting target accepted") } catch CoreError.idempotencyConflict { }
    let finished = try await reopened.run(id: first.id)
    #expect(finished.status == .completed)
    #expect(finished.message.contains("no cleanup"))
    #expect(try await store.get(id: first.id).status == .completed)
}
@Test func insufficientAndCapacityFailureAreHonest() async throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = JobStore(directory: root, capacityURL: root)
    let job = try await store.enqueue(targetBytes: Int64.max, key: "large")
    let result = try await store.run(id: job.id)
    #expect(result.status == .insufficient)
    #expect(result.message.contains("No cleanup rule"))
    let failing = JobStore(directory: root, capacityURL: root.appendingPathComponent("missing"))
    let failJob = try await failing.enqueue(targetBytes: 1, key: "fail")
    #expect(try await failing.run(id: failJob.id).status == .failed)
}
@Test func simultaneousIdempotentRequestsShareOneJob() async throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let a = JobStore(directory: root); let b = JobStore(directory: root)
    async let first = a.enqueue(targetBytes: 5, key: "same")
    async let second = b.enqueue(targetBytes: 5, key: "same")
    let pair = try await (first, second)
    #expect(pair.0.id == pair.1.id)
    #expect(try await a.jobs().count == 1)
}
@Test func persistenceFailureIsNotAcknowledged() async throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let file = root.appendingPathComponent("not-a-directory"); try Data().write(to: file)
    let store = JobStore(directory: file)
    do { _ = try await store.enqueue(targetBytes: 1, key: "x"); Issue.record("Persistence failure was acknowledged") } catch { }
}
@Test func comparisonsRejectCoverageGapsAndDifferentRoots() {
    let entry = InventoryEntry(path: "/fixture/a", name: "a", apparentBytes: 12, allocatedBytes: 12, modifiedAt: nil, isDirectory: false, coverage: .complete)
    let before = InventorySnapshot(root: "/fixture", entries: [entry], errors: [], capacity: nil, scannerVersion: 2, volumeUUID: "fixture-volume", rootDevice: 1, rootInode: 2)
    let updated = InventoryEntry(path: "/fixture/a", name: "a", apparentBytes: 20, allocatedBytes: 20, modifiedAt: nil, isDirectory: false, coverage: .complete)
    let after = InventorySnapshot(root: "/fixture", entries: [updated], errors: [], capacity: nil, scannerVersion: 2, volumeUUID: "fixture-volume", rootDevice: 1, rootInode: 2)
    #expect(compareSnapshots(before, after).first?.changeBytes == 8)
    let unavailable = InventoryEntry(path: "/fixture/a", name: "a", apparentBytes: 0, allocatedBytes: nil, modifiedAt: nil, isDirectory: false, coverage: .partial)
    let partial = InventorySnapshot(root: "/fixture", entries: [unavailable], errors: ["Permission denied"], capacity: nil, scannerVersion: 2, volumeUUID: "fixture-volume", rootDevice: 1, rootInode: 2)
    let different = InventorySnapshot(root: "/other", entries: [updated], errors: [], capacity: nil, scannerVersion: 2, volumeUUID: "fixture-volume", rootDevice: 1, rootInode: 2)
    #expect(compareSnapshots(before, partial).isEmpty)
    #expect(compareSnapshots(before, different).isEmpty)
}
@Test func unchangedSuggestionsExcludeDirectories() {
    let date = Date(timeIntervalSince1970: 100)
    let directory = InventoryEntry(path: "/folder", name: "folder", apparentBytes: 1000, allocatedBytes: nil, modifiedAt: date, isDirectory: true, coverage: .complete)
    let file = InventoryEntry(path: "/file", name: "file", apparentBytes: 4, allocatedBytes: nil, modifiedAt: date, isDirectory: false, coverage: .complete)
    let snapshot = InventorySnapshot(root: "/", entries: [directory, file], errors: [], capacity: nil)
    #expect(largeUnchangedFiles(in: snapshot, before: Date(timeIntervalSince1970: 200)).map(\.name) == ["file"])
}
@Test func readingJobHistoryDoesNotRewriteLedger() async throws {
    let root = try temporary(); defer { try? FileManager.default.removeItem(at: root) }
    let store = JobStore(directory: root, capacityURL: root)
    let job = try await store.enqueue(targetBytes: 1, key: "read-only")
    _ = try await store.run(id: job.id)
    let ledger = root.appendingPathComponent("jobs.json")
    let fixed = Date(timeIntervalSince1970: 1_000_000_000)
    try FileManager.default.setAttributes([.modificationDate: fixed], ofItemAtPath: ledger.path)
    let before = try Data(contentsOf: ledger)
    #expect(try await store.get(id: job.id).status == .completed)
    #expect(try await store.jobs().count == 1)
    #expect(try Data(contentsOf: ledger) == before)
    #expect(try FileManager.default.attributesOfItem(atPath: ledger.path)[.modificationDate] as? Date == fixed)
}
