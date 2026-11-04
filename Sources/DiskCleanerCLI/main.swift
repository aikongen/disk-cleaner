import Foundation
import DiskCleanerCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

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
        case "status", "wait":
            guard args.count == 2, let id = UUID(uuidString: args[1]) else { throw CoreError.invalidRequest }
            var current = try await store.get(id: id)
            if command == "wait" {
                while current.status == .queued || current.status == .running {
                    try await Task.sleep(for: .milliseconds(200)); current = try await store.get(id: id)
                }
            }
            job = current
        default: throw CoreError.invalidRequest
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(job); FileHandle.standardOutput.write(data); FileHandle.standardOutput.write(Data("\n".utf8))
    }
}
