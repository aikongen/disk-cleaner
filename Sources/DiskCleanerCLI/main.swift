import Foundation
import DiskCleanerCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

private struct WaitTimeout: LocalizedError {
    let raw: String
    let id: UUID
    var errorDescription: String? { "Timed out after \(raw) seconds waiting for job \(id.uuidString)" }
}

/// Matches ^[0-9]+(\.[0-9]+)?$ using ASCII digits only.
private func isPlainDecimal(_ text: String) -> Bool {
    let parts = text.utf8.split(separator: UInt8(ascii: "."), maxSplits: 2, omittingEmptySubsequences: false)
    guard parts.count == 1 || parts.count == 2 else { return false }
    for part in parts {
        if part.isEmpty { return false }
        for byte in part where byte < UInt8(ascii: "0") || byte > UInt8(ascii: "9") { return false }
    }
    return true
}

@main struct CLI {
    static func main() async {
        do { try await run() } catch {
            let object = ["error": error.localizedDescription]
            if let data = try? JSONSerialization.data(withJSONObject: object), let line = String(data: data, encoding: .utf8) { FileHandle.standardError.write(Data((line + "\n").utf8)) }
            exit(1)
        }
    }
    // Test-only fixture mode requires an existing marker; never silently uses the real store.
    static func stateDirectory() throws -> URL {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["DISK_CLEANER_FIXTURE_MODE"] != nil || environment["DISK_CLEANER_FIXTURE_DIR"] != nil {
            guard environment["DISK_CLEANER_FIXTURE_MODE"] == "1",
                  let path = environment["DISK_CLEANER_FIXTURE_DIR"], path.hasPrefix("/"),
                  FileManager.default.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent(".disk-cleaner-fixture").path)
            else { throw CoreError.invalidRequest }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        #endif
        return try DataLocation.applicationSupport()
    }
    static func run() async throws {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else { throw CoreError.invalidRequest }
        // Capability is checked before resolving any state path, even in release builds.
        if command == "fixture-capability" {
            #if DEBUG
            guard args.count == 1 else { throw CoreError.invalidRequest }
            FileHandle.standardOutput.write(Data("disk-cleaner-debug-fixture-v1\n".utf8))
            return
            #else
            throw CoreError.invalidRequest
            #endif
        }
        let store = JobStore(directory: try stateDirectory())
        let job: CleanupJob
        switch command {
        case "request":
            guard args.count == 3, let target = Int64(args[1]) else { throw CoreError.invalidRequest }
            job = try await store.enqueue(targetBytes: target, key: args[2])
            if job.status == .queued {
                do {
                    let process = Process()
                    guard let executable = Bundle.main.executableURL else { throw CoreError.invalidRequest }
                    process.executableURL = executable.standardizedFileURL
                    process.arguments = ["worker", job.id.uuidString]
                    process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
                    try process.run()
                } catch { try await store.fail(id: job.id, reason: "Could not start worker: \(error.localizedDescription)"); throw error }
            }
        case "worker":
            guard args.count == 2, let id = UUID(uuidString: args[1]) else { throw CoreError.invalidRequest }
            job = try await store.run(id: id)
        case "status":
            guard args.count == 2, let id = UUID(uuidString: args[1]) else { throw CoreError.invalidRequest }
            job = try await store.get(id: id)
        case "wait":
            // All argument parsing happens before the job is read.
            guard args.count == 2 || args.count == 4, let id = UUID(uuidString: args[1]) else { throw CoreError.invalidRequest }
            var rawTimeout: String?
            var seconds = 0.0
            if args.count == 4 {
                let raw = args[3]
                guard args[2] == "--timeout", isPlainDecimal(raw), let value = Double(raw), value.isFinite, value > 0 else { throw CoreError.invalidRequest }
                rawTimeout = raw; seconds = value
            }
            let clock = ContinuousClock()
            let deadline: ContinuousClock.Instant? = rawTimeout == nil ? nil : clock.now + .seconds(min(seconds, 1_000_000_000))
            var current = try await store.get(id: id)
            while current.status == .queued || current.status == .running {
                var pause = Duration.milliseconds(200)
                if let deadline {
                    let now = clock.now
                    if now >= deadline { throw WaitTimeout(raw: rawTimeout ?? "", id: id) }
                    pause = min(pause, deadline - now)
                }
                try await Task.sleep(for: pause); current = try await store.get(id: id)
            }
            job = current
        default: throw CoreError.invalidRequest
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
