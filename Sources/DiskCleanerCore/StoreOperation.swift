import Foundation
import Darwin

// One advisory lease covers the cross-process scan/manual-action interval, in
// addition to each ledger's existing atomic-write lock. Public operations acquire
// once; their private ledger helpers never reacquire this non-reentrant lock.
enum StoreOperationLock {
    static func acquire(directory: URL) throws -> (key: String, descriptor: Int32) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let resolved = realpath(directory.path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { free(resolved) }
        let canonical = String(cString: resolved)
        let directoryFD = open(canonical, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directoryFD >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(directoryFD) }
        var fd = openat(directoryFD, ".operation.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        // macOS 27 can report a transient ENOENT for O_CREAT|O_NOFOLLOW while another thread creates the same name (reproduced by two concurrent JobStore.enqueue calls). O_NOFOLLOW still rejects a symlink leaf (ELOOP) on retry.
        var attempts = 0
        while fd < 0 && errno == ENOENT && attempts < 50 {
            attempts += 1; usleep(2_000)
            fd = openat(directoryFD, ".operation.lock", O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, mode_t(0o600))
        }
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            let code = errno; close(fd)
            if code == EWOULDBLOCK || code == EAGAIN { throw InventoryOperationError.busy }
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        return (canonical, fd)
    }
    static func release(_ descriptor: Int32) { flock(descriptor, LOCK_UN); close(descriptor) }
    static func withExclusive<T>(directory: URL, _ body: () throws -> T) throws -> T {
        let lease = try acquire(directory: directory)
        defer { release(lease.descriptor) }
        return try body()
    }
}

private struct ManualRescanLedger: Codable { var version = 1; var roots: [String: Date] = [:] }
enum ManualRescanJournal {
    static func roots(directory: URL) throws -> [String: Date] {
        try DiskFile(directory: directory, name: "rescan-required.json", fallback: ManualRescanLedger()).read {
            guard $0.version == 1 else { throw ManualTrashError.requiresRescan }
            return $0.roots
        }
    }
    static func mark(roots: Set<String>, at date: Date, directory: URL) throws {
        try DiskFile(directory: directory, name: "rescan-required.json", fallback: ManualRescanLedger()).locked {
            guard $0.version == 1 else { throw ManualTrashError.requiresRescan }
            for root in roots { if $0.roots[root] == nil { $0.roots[root] = date } }
        }
    }
    static func clear(root: String, directory: URL) throws {
        guard try roots(directory: directory)[root] != nil else { return }
        try DiskFile(directory: directory, name: "rescan-required.json", fallback: ManualRescanLedger()).locked {
            guard $0.version == 1 else { throw ManualTrashError.requiresRescan }
            $0.roots.removeValue(forKey: root)
        }
    }
}
