import Foundation
import Testing
@testable import DiskCleanerCore

private func jobFixtureDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-job-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Test func jobSurvivesReopenAndSameKeyReplay() async throws {
    let dir = try jobFixtureDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let first = try await JobStore(directory: dir).enqueue(targetBytes: 7, key: "fixture")
    let replay = try await JobStore(directory: dir).enqueue(targetBytes: 7, key: "fixture")
    #expect(first.id == replay.id)
    do {
        _ = try await JobStore(directory: dir).enqueue(targetBytes: 8, key: "fixture")
        Issue.record("different target was accepted for the same key")
    } catch CoreError.idempotencyConflict { } 
}

@Test func corruptJobLedgerFailsWithoutReplacingHistory() async throws {
    let dir = try jobFixtureDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    let path = dir.appendingPathComponent("jobs.json")
    let corrupt = Data("{\"jobs\":[".utf8)
    try corrupt.write(to: path)
    do {
        _ = try await JobStore(directory: dir).enqueue(targetBytes: 1, key: "fixture")
        Issue.record("corrupt ledger was accepted")
    } catch { }
    #expect(try Data(contentsOf: path) == corrupt)
}

@Test func jobWriteFailureDoesNotReturnAcknowledgement() async throws {
    let dir = try jobFixtureDirectory(); defer { try? FileManager.default.removeItem(at: dir) }
    // A directory at the intended lock-file path is a deterministic isolated write/open failure.
    try FileManager.default.createDirectory(at: dir.appendingPathComponent("jobs.json.lock"), withIntermediateDirectories: false)
    do {
        _ = try await JobStore(directory: dir).enqueue(targetBytes: 1, key: "fixture")
        Issue.record("failed persistence returned a job")
    } catch { }
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("jobs.json").path))
}
