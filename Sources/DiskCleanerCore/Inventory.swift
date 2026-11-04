import Foundation
import Darwin

public actor InventoryStore {
    private let directory: URL
    private let operationGate: InventoryOperationGate
    public init(directory: URL, operationGate: InventoryOperationGate = .shared) { self.directory = directory; self.operationGate = operationGate }
    public func snapshots() throws -> [InventorySnapshot] {
        let invalidations = try ManualRescanJournal.roots(directory: directory)
        return try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).read { ledger in
            ledger.snapshots.map { snapshot in
                if let date = invalidations[snapshot.root] { return snapshot.invalidating(at: snapshot.invalidatedAt ?? date) }
                return snapshot
            }
        }
    }
    public func scan(root: URL, retention: SnapshotRetention = .thirty) async throws -> InventorySnapshot {
        try await scan(root: root, entryLimit: 100_000, onDirectoryObserved: nil, retention: retention)
    }
    // Internal injection is used only for bounded, isolated scanner fixtures.
    func scan(root: URL, entryLimit: Int, onDirectoryObserved: (@Sendable (URL) -> Void)?, retention: SnapshotRetention = .thirty) async throws -> InventorySnapshot {
        guard entryLimit > 0 else { throw CoreError.invalidRequest }
        let directory = self.directory
        return try await operationGate.perform(key: directory.standardizedFileURL.path) {
            let snapshot = try await Self.observe(root: root, entryLimit: entryLimit, onDirectoryObserved: onDirectoryObserved)
            try Task.checkCancellation()
            let invalidations = try ManualRescanJournal.roots(directory: directory)
            try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).locked { ledger in
                try Task.checkCancellation()
                if let date = invalidations[snapshot.root] {
                    for index in ledger.snapshots.indices where ledger.snapshots[index].root == snapshot.root {
                        ledger.snapshots[index] = ledger.snapshots[index].invalidating(at: ledger.snapshots[index].invalidatedAt ?? date)
                    }
                }
                ledger.snapshots.append(snapshot)
                if ledger.snapshots.count > retention.rawValue { ledger.snapshots.removeFirst(ledger.snapshots.count - retention.rawValue) }
            }
            try ManualRescanJournal.clear(root: snapshot.root, directory: directory)
            return snapshot
        }
    }
    public func applyRetention(_ retention: SnapshotRetention) async throws {
        let directory = self.directory
        try await operationGate.perform(key: directory.standardizedFileURL.path) {
            try DiskFile(directory: directory, name: "snapshots.json", fallback: SnapshotLedger()).locked { ledger in
                if ledger.snapshots.count > retention.rawValue { ledger.snapshots.removeFirst(ledger.snapshots.count - retention.rawValue) }
            }
        }
    }
    private nonisolated static func observe(root: URL, entryLimit: Int, onDirectoryObserved: (@Sendable (URL) -> Void)?) async throws -> InventorySnapshot {
        let task = Task.detached(priority: .userInitiated) {
            try Scanner.observe(root: root, limit: entryLimit, onDirectoryObserved: onDirectoryObserved)
        }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

/// Path labels describe observations; all descendant opens are anchored to held directory
/// descriptors and refuse links. A scan is not an atomic filesystem snapshot.
private enum Scanner {
    private struct Frame { let stream: UnsafeMutablePointer<DIR>; let path: String; let sameVolume: Bool }
    private static func capacityForDescriptor(_ fd: Int32) -> VolumeCapacity? {
        guard fd >= 0 else { return nil }
        var info = statfs()
        guard fstatfs(fd, &info) == 0, info.f_bsize > 0 else { return nil }
        let (total, totalOverflow) = UInt64(info.f_blocks).multipliedReportingOverflow(by: UInt64(info.f_bsize))
        let (free, freeOverflow) = UInt64(info.f_bfree).multipliedReportingOverflow(by: UInt64(info.f_bsize))
        guard !totalOverflow, !freeOverflow, let totalBytes = Int64(exactly: total), let availableBytes = Int64(exactly: free) else { return nil }
        return VolumeCapacity(totalBytes: totalBytes, availableBytes: availableBytes)
    }
    static func observe(root: URL, limit: Int, onDirectoryObserved: (@Sendable (URL) -> Void)?) throws -> InventorySnapshot {
        // Resolve ancestor aliases using POSIX realpath, but keep the selected
        // leaf unresolved so O_NOFOLLOW still rejects a symlink root.
        let base = URL(fileURLWithPath: try FileIdentityReader.rootPathWithoutFollowingLeaf(root))
        let rootFD = open(base.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard rootFD >= 0 else { throw CoreError.invalidRoot }
        var rootMetadata = stat()
        guard fstat(rootFD, &rootMetadata) == 0 else {
            let code = errno
            close(rootFD)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        let rootIdentity = FileIdentity(rootMetadata)
        var rootAncestors: [InventoryPathIdentity]?
        var identityFailure: String?
        do {
            let chain = try FileIdentityReader.rootChain(base.path)
            if chain.last?.identity.sameObject(as: rootIdentity) == true { rootAncestors = chain }
            else { identityFailure = "Folder identity chain changed during observation; manual Trash is unavailable." }
        } catch { identityFailure = "Folder identity chain could not be verified; manual Trash is unavailable: \(error.localizedDescription)" }
        let candidateVolume = try? base.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        var pathMetadata = stat()
        let identityMatches = lstat(base.path, &pathMetadata) == 0 && pathMetadata.st_dev == rootMetadata.st_dev && pathMetadata.st_ino == rootMetadata.st_ino
        let volumeUUID = identityMatches ? candidateVolume : nil
        // Keep an independent descriptor so capacity belongs to the opened root,
        // even if its pathname is replaced before the scan completes.
        let capacityFD = dup(rootFD)
        defer { if capacityFD >= 0 { close(capacityFD) } }
        guard let rootStream = fdopendir(rootFD) else {
            let code = errno
            close(rootFD)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        var stack = [Frame(stream: rootStream, path: base.path, sameVolume: true)]
        defer { for frame in stack { closedir(frame.stream) } }
        var entries: [InventoryEntry] = []
        var errors: [String] = []
        if let identityFailure { errors.append(identityFailure) }
        var incompletePaths = Set<String>()
        if volumeUUID == nil { errors.append("Volume identity unavailable; comparisons are unavailable") }
        var observed = 0
        var warnedHardLink = false
        var warnedOtherVolume = false
        while let frame = stack.last {
            try Task.checkCancellation()
            errno = 0
            guard let item = readdir(frame.stream) else {
                let code = errno
                if code != 0 { errors.append("\(frame.path): directory read failed (errno \(code))"); incompletePaths.insert(frame.path) }
                closedir(frame.stream)
                stack.removeLast()
                continue
            }
            var nameBytes = item.pointee.d_name
            let nameCapacity = MemoryLayout.size(ofValue: nameBytes)
            let name = withUnsafePointer(to: &nameBytes) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: nameCapacity) { String(validatingUTF8: $0) }
            }
            if name == "." || name == ".." { continue }
            // Count all directory entries, including unrepresentable names and omissions.
            if observed >= limit {
                errors.append("Observation limit reached; scan incomplete")
                for pending in stack { incompletePaths.insert(pending.path) }
                break
            }
            observed += 1
            guard let name else { errors.append("\(frame.path): a filename could not be represented"); incompletePaths.insert(frame.path); continue }
            let path = (frame.path as NSString).appendingPathComponent(name)
            var metadata = stat()
            guard fstatat(dirfd(frame.stream), name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
                errors.append("\(path): metadata unavailable (errno \(errno))")
                incompletePaths.insert(frame.path)
                continue
            }
            let kind = metadata.st_mode & mode_t(S_IFMT)
            if kind == mode_t(S_IFLNK) {
                errors.append("\(path): symbolic link omitted")
                incompletePaths.insert(frame.path)
                continue
            }
            let isDirectory = kind == mode_t(S_IFDIR)
            guard isDirectory || kind == mode_t(S_IFREG) else {
                errors.append("\(path): unsupported filesystem object omitted")
                incompletePaths.insert(frame.path)
                continue
            }
            var allocated: Int64? = 0
            var coverage: Coverage = .complete
            if !frame.sameVolume || metadata.st_dev != rootMetadata.st_dev {
                // Scope identity covers the selected root's volume only.
                coverage = .partial
                if !warnedOtherVolume {
                    errors.append("Other mounted volumes were observed; their entries are not comparable")
                    warnedOtherVolume = true
                }
            }
            var apparent: Int64 = 0
            if !isDirectory {
                guard metadata.st_size >= 0 else {
                    errors.append("\(path): file size unavailable; entry omitted")
                    incompletePaths.insert(frame.path)
                    continue
                }
                apparent = Int64(metadata.st_size)
                if metadata.st_blocks < 0 || Int64(metadata.st_blocks) > Int64.max / 512 {
                    allocated = nil
                    coverage = .partial
                    errors.append("\(path): allocated size unavailable")
                } else {
                    allocated = Int64(metadata.st_blocks) * 512
                    if metadata.st_nlink > 1 {
                        // A pathname cannot claim exclusive ownership of shared blocks.
                        allocated = nil
                        coverage = .partial
                        if !warnedHardLink {
                            errors.append("Hard-linked file allocation is unknown; links may share storage")
                            warnedHardLink = true
                        }
                    }
                }
            }
            let date = Date(timeIntervalSince1970: Double(metadata.st_mtimespec.tv_sec) + Double(metadata.st_mtimespec.tv_nsec) / 1_000_000_000)
            entries.append(InventoryEntry(path: path, name: name, apparentBytes: apparent, allocatedBytes: allocated, modifiedAt: date, isDirectory: isDirectory, coverage: coverage, identity: FileIdentity(metadata)))
            guard isDirectory else { continue }
            onDirectoryObserved?(URL(fileURLWithPath: path, isDirectory: true))
            let childFD = openat(dirfd(frame.stream), name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard childFD >= 0 else { errors.append("\(path): directory unavailable or changed (errno \(errno))"); incompletePaths.insert(path); continue }
            var opened = stat()
            guard fstat(childFD, &opened) == 0, opened.st_dev == metadata.st_dev, opened.st_ino == metadata.st_ino else {
                close(childFD)
                errors.append("\(path): directory changed during observation")
                incompletePaths.insert(path)
                continue
            }
            guard let childStream = fdopendir(childFD) else {
                let code = errno
                close(childFD)
                errors.append("\(path): directory stream unavailable (errno \(code))")
                incompletePaths.insert(path)
                continue
            }
            stack.append(Frame(stream: childStream, path: path, sameVolume: frame.sameVolume && metadata.st_dev == rootMetadata.st_dev))
        }
        // A gap affects its directory and ancestors, not unrelated siblings.
        for i in entries.indices where entries[i].isDirectory && incompletePaths.contains(entries[i].path) {
            let e = entries[i]
            entries[i] = InventoryEntry(path: e.path, name: e.name, apparentBytes: e.apparentBytes, allocatedBytes: e.allocatedBytes, modifiedAt: e.modifiedAt, isDirectory: true, coverage: .partial, identity: e.identity)
        }
        var lookup: [String: Int] = [:]
        for (index, entry) in entries.enumerated() { lookup[entry.path] = index }
        for index in entries.indices.reversed() {
            try Task.checkCancellation()
            let child = entries[index]
            let parent = InventoryPaths.parent(child.path)
            guard let parentIndex = lookup[parent] else { continue }
            let prior = entries[parentIndex]
            let (sum, overflow) = prior.apparentBytes.addingReportingOverflow(child.apparentBytes)
            let allocated: Int64? = prior.allocatedBytes.flatMap { p in child.allocatedBytes.flatMap { c in
                let (value, overflow) = p.addingReportingOverflow(c)
                return overflow ? nil : value
            } }
            if overflow { errors.append("\(parent): size total exceeded representation") }
            entries[parentIndex] = InventoryEntry(path: prior.path, name: prior.name, apparentBytes: overflow ? Int64.max : sum, allocatedBytes: allocated, modifiedAt: prior.modifiedAt, isDirectory: true, coverage: !overflow && allocated != nil && prior.coverage == .complete && child.coverage == .complete ? .complete : .partial, identity: prior.identity)
        }
        return InventorySnapshot(id: UUID(), root: base.path, createdAt: Date(), entries: entries, errors: errors, capacity: capacityForDescriptor(capacityFD), scannerVersion: 2, volumeUUID: volumeUUID, rootDevice: Int64(rootMetadata.st_dev), rootInode: UInt64(rootMetadata.st_ino), rootIdentity: rootIdentity, rootAncestors: rootAncestors)
    }
}

public func capacityAt(_ url: URL) throws -> VolumeCapacity {
    let attributes = try FileManager.default.attributesOfFileSystem(forPath: url.path)
    guard let total = attributes[.systemSize] as? NSNumber, let free = attributes[.systemFreeSize] as? NSNumber else { throw CocoaError(.fileReadUnknown) }
    return VolumeCapacity(totalBytes: total.int64Value, availableBytes: free.int64Value)
}
