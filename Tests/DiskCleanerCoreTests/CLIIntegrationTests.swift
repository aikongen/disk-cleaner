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

// MARK: - wait --timeout

private func makeFixture() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("disk-cleaner-cli-wait-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data().write(to: dir.appendingPathComponent(".disk-cleaner-fixture"))
    return dir
}

private func writeLedger(_ dir: URL, jobs: [CleanupJob]) throws {
    let data = try JSONEncoder().encode(JobLedger(jobs: jobs))
    try data.write(to: dir.appendingPathComponent("jobs.json"))
}

private func requireCapability(_ executable: URL) throws {
    let capability = try invokeCLI(executable, ["fixture-capability"], fixture: nil)
    try #require(capability.status == 0 && String(data: capability.output, encoding: .utf8) == "disk-cleaner-debug-fixture-v1\n", "CLI fixture capability unavailable")
}

private func errorText(_ result: CLIResult) throws -> String? {
    let parsed = try object(result.error)
    #expect(parsed.count == 1)
    return parsed["error"] as? String
}

@Test func waitTimeoutOnRunningJobExitsOneAndLeavesJobUnchanged() throws {
    let executable = try builtCLI()
    try requireCapability(executable)
    let dir = try makeFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let job = CleanupJob(key: "running-key", targetBytes: 1, status: .running, message: "running")
    try writeLedger(dir, jobs: [job])
    let ledger = dir.appendingPathComponent("jobs.json")
    let before = try Data(contentsOf: ledger)
    let id = job.id.uuidString
    // The raw text the caller wrote is echoed back unchanged.
    for written in ["0.5", "1.50", "2"] {
        let result = try invokeCLI(executable, ["wait", id, "--timeout", written], fixture: dir)
        #expect(result.status == 1)
        #expect(result.output.isEmpty)
        #expect(result.error == Data("{\"error\":\"Timed out after \(written) seconds waiting for job \(id)\"}\n".utf8))
        #expect(try errorText(result) == "Timed out after \(written) seconds waiting for job \(id)")
        #expect(try Data(contentsOf: ledger) == before)
    }
    let status = try invokeCLI(executable, ["status", id], fixture: dir)
    #expect(status.status == 0)
    #expect(try object(status.output)["status"] as? String == "running")
    #expect(try Data(contentsOf: ledger) == before)
}

@Test func waitTimeoutOnFinishedJobMatchesPlainWait() throws {
    let executable = try builtCLI()
    try requireCapability(executable)
    let dir = try makeFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let job = CleanupJob(key: "done-key", targetBytes: 1, status: .completed, beforeBytes: 10, afterBytes: 20, message: "done")
    try writeLedger(dir, jobs: [job])
    let id = job.id.uuidString
    let plain = try invokeCLI(executable, ["wait", id], fixture: dir)
    try #require(plain.status == 0)
    #expect(try object(plain.output)["status"] as? String == "completed")
    for raw in ["5", "0.5"] {
        let limited = try invokeCLI(executable, ["wait", id, "--timeout", raw], fixture: dir)
        #expect(limited.status == 0)
        #expect(limited.output == plain.output)
        #expect(limited.error.isEmpty)
    }
}

@Test func plainWaitStillWaitsForRealRequestedJob() throws {
    let executable = try builtCLI()
    try requireCapability(executable)
    let dir = try makeFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let first = try invokeCLI(executable, ["request", "1", "plain-wait-key"], fixture: dir)
    try #require(first.status == 0)
    let id = try #require(try object(first.output)["id"] as? String)
    let terminal = try invokeCLI(executable, ["wait", id], fixture: dir)
    #expect(terminal.status == 0)
    #expect(try object(terminal.output)["id"] as? String == id)
    #expect(try object(terminal.output)["status"] as? String == "completed")
}

@Test func waitTimeoutRefusedFormsReportInvalidRequestWithoutReadingJob() throws {
    let executable = try builtCLI()
    try requireCapability(executable)
    let dir = try makeFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let missing = UUID().uuidString   // not in the ledger: reading first would say "Job not found"
    let forms: [[String]] = [
        ["wait", missing, "--timeout", "abc"],
        ["wait", missing, "--timeout", "0"],
        ["wait", missing, "--timeout", "0.0"],
        ["wait", missing, "--timeout", "-1"],
        ["wait", missing, "--timeout", "nan"],
        ["wait", missing, "--timeout", "inf"],
        ["wait", missing, "--timeout", ""],
        ["wait", missing, "--timeout"],
        ["wait", missing, "--timeout", "5", "extra"],
        ["wait", missing, "--bogus", "5"],
        ["wait", missing, "5"],
        ["wait", "--timeout", "5", missing],
    ]
    for form in forms {
        let result = try invokeCLI(executable, form, fixture: dir)
        #expect(result.status == 1, "\(form)")
        #expect(result.output.isEmpty, "\(form)")
        #expect(result.error == Data("{\"error\":\"Invalid request\"}\n".utf8), "\(form)")
    }
    // One refused form on an existing running job leaves the ledger untouched.
    let job = CleanupJob(key: "refuse-key", targetBytes: 1, status: .running, message: "running")
    try writeLedger(dir, jobs: [job])
    let ledger = dir.appendingPathComponent("jobs.json")
    let before = try Data(contentsOf: ledger)
    let result = try invokeCLI(executable, ["wait", job.id.uuidString, "--timeout", "0"], fixture: dir)
    #expect(result.status == 1)
    #expect(result.output.isEmpty)
    #expect(result.error == Data("{\"error\":\"Invalid request\"}\n".utf8))
    #expect(try Data(contentsOf: ledger) == before)
}

@Test func statusRefusesTimeoutFlag() throws {
    let executable = try builtCLI()
    try requireCapability(executable)
    let dir = try makeFixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let job = CleanupJob(key: "status-key", targetBytes: 1, status: .running, message: "running")
    try writeLedger(dir, jobs: [job])
    let id = job.id.uuidString
    for form in [["status", id, "--timeout", "1"], ["status", id, "--timeout"]] {
        let result = try invokeCLI(executable, form, fixture: dir)
        #expect(result.status == 1, "\(form)")
        #expect(result.output.isEmpty, "\(form)")
        #expect(result.error == Data("{\"error\":\"Invalid request\"}\n".utf8), "\(form)")
    }
}
