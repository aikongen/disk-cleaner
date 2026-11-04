import Foundation
import Testing
@testable import DiskCleanerCore

private final class CLIBundleMarker: NSObject { }
private struct CLIResult { let status: Int32; let output: Data; let error: Data }

private func builtCLI() throws -> URL {
    // Only the product alongside this test bundle is allowed; never search PATH or .build.
    let bundle = Bundle(for: CLIBundleMarker.self).bundleURL
    let executable = bundle.deletingLastPathComponent().appendingPathComponent("disk-cleanerctl")
    return try #require(FileManager.default.isExecutableFile(atPath: executable.path) ? executable : nil,
                        "Same-build CLI not found next to test bundle; integration test is blocked")
}

private func invokeCLI(_ executable: URL, _ args: [String], fixture: URL?) throws -> CLIResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = args
    var environment = ProcessInfo.processInfo.environment
    environment["DISK_CLEANER_FIXTURE_MODE"] = "1"
    environment["DISK_CLEANER_FIXTURE_DIR"] = fixture?.path
    process.environment = environment
    let stdout = Pipe(), stderr = Pipe()
    process.standardOutput = stdout; process.standardError = stderr
    try process.run()
    process.waitUntilExit()
    return CLIResult(status: process.terminationStatus,
                     output: stdout.fileHandleForReading.readDataToEndOfFile(),
                     error: stderr.fileHandleForReading.readDataToEndOfFile())
}

private func object(_ data: Data) throws -> [String: Any] {
    try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Test func cliRequestsReplayAndStatusInAnIsolatedFixture() throws {
    let executable = try builtCLI()
    // This preflight never opens state and prevents a release binary using real Application Support.
    let capability = try invokeCLI(executable, ["fixture-capability"], fixture: nil)
    try #require(capability.status == 0 && String(data: capability.output, encoding: .utf8) == "disk-cleaner-debug-fixture-v1\n", "CLI fixture capability unavailable")
    let noFixture = try invokeCLI(executable, ["request", "1", "missing"], fixture: nil)
    #expect(noFixture.status != 0)
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-cli-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data().write(to: dir.appendingPathComponent(".disk-cleaner-fixture"))
    let first = try invokeCLI(executable, ["request", "1", "fixture-key"], fixture: dir)
    try #require(first.status == 0)
    let id = try #require(try object(first.output)["id"] as? String)
    let replay = try invokeCLI(executable, ["request", "1", "fixture-key"], fixture: dir)
    try #require(replay.status == 0)
    #expect(try object(replay.output)["id"] as? String == id)
    let conflict = try invokeCLI(executable, ["request", "2", "fixture-key"], fixture: dir)
    #expect(conflict.status != 0)
    let terminal = try invokeCLI(executable, ["wait", id], fixture: dir)
    try #require(terminal.status == 0)
    #expect(try object(terminal.output)["id"] as? String == id)
    #expect(try object(terminal.output)["status"] as? String == "completed")
    let reopened = try invokeCLI(executable, ["status", id], fixture: dir)
    try #require(reopened.status == 0)
    #expect(try object(reopened.output)["status"] as? String == "completed")

    let ledger = dir.appendingPathComponent("jobs.json")
    let truncated = Data("{\"jobs\":[".utf8)
    try truncated.write(to: ledger)
    let badStatus = try invokeCLI(executable, ["status", id], fixture: dir)
    #expect(badStatus.status != 0)
    #expect(try Data(contentsOf: ledger) == truncated)

    let blocked = dir.appendingPathComponent("blocked", isDirectory: true)
    try FileManager.default.createDirectory(at: blocked, withIntermediateDirectories: false)
    try Data().write(to: blocked.appendingPathComponent(".disk-cleaner-fixture"))
    try FileManager.default.createDirectory(at: blocked.appendingPathComponent("jobs.json.lock"), withIntermediateDirectories: false)
    let failed = try invokeCLI(executable, ["request", "1", "write-failure"], fixture: blocked)
    #expect(failed.status != 0)
    #expect(!FileManager.default.fileExists(atPath: blocked.appendingPathComponent("jobs.json").path))
}

@Test func cliRequestWaitsForCanonicalCrossProcessOperationLease() async throws {
    let executable = try builtCLI()
    let capability = try invokeCLI(executable, ["fixture-capability"], fixture: nil)
    try #require(capability.status == 0 && String(data: capability.output, encoding: .utf8) == "disk-cleaner-debug-fixture-v1\n")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-cli-lock-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try Data().write(to: dir.appendingPathComponent(".disk-cleaner-fixture"))
    let lease = try StoreOperationLock.acquire(directory: dir)
    var released = false
    defer { if !released { StoreOperationLock.release(lease.descriptor) } }
    let process = Process(); process.executableURL = executable
    process.arguments = ["request", "1", "canonical-lock-fixture"]
    var environment = ProcessInfo.processInfo.environment
    environment["DISK_CLEANER_FIXTURE_MODE"] = "1"; environment["DISK_CLEANER_FIXTURE_DIR"] = dir.path
    process.environment = environment
    let output = Pipe(), error = Pipe(); process.standardOutput = output; process.standardError = error
    try process.run()
    defer { if process.isRunning { process.terminate(); process.waitUntilExit() } }
    try await Task.sleep(for: .milliseconds(400))
    #expect(process.isRunning)
    #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("jobs.json").path))
    StoreOperationLock.release(lease.descriptor); released = true
    for _ in 0..<100 {
        if !process.isRunning { break }
        try await Task.sleep(for: .milliseconds(50))
    }
    try #require(!process.isRunning, "fixture CLI did not resume after operation lease release")
    #expect(process.terminationStatus == 0)
    let acknowledgement = try object(output.fileHandleForReading.readDataToEndOfFile())
    let id = try #require(acknowledgement["id"] as? String)
    let completed = try invokeCLI(executable, ["wait", id], fixture: dir)
    #expect(completed.status == 0)
    #expect(try object(completed.output)["status"] as? String == "completed")
}
