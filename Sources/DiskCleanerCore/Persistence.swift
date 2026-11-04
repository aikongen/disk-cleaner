import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

struct DiskFile<Value: Codable> {
    let directory: URL
    let name: String
    let fallback: Value
    func read<T>(_ body: (Value) throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("\(name).lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_SH) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        let url = directory.appendingPathComponent(name)
        let value = fm.fileExists(atPath: url.path) ? try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) : fallback
        return try body(value)
    }
    func locked<T>(_ body: (inout Value) throws -> T) throws -> T {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = open(directory.appendingPathComponent("\(name).lock").path, O_CREAT | O_RDWR, mode_t(0o600))
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { flock(fd, LOCK_UN) }
        let url = directory.appendingPathComponent(name)
        var value = fm.fileExists(atPath: url.path) ? try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) : fallback
        let result = try body(&value)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
        let written = open(url.path, O_RDONLY)
        guard written >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(written) }
        guard fsync(written) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let folder = open(directory.path, O_RDONLY)
        guard folder >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(folder) }
        guard fsync(folder) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return result
    }
}
struct SnapshotLedger: Codable { var version = 1; var snapshots: [InventorySnapshot] = [] }
struct JobLedger: Codable { var version = 1; var jobs: [CleanupJob] = [] }
