import Foundation
import Darwin

public struct FileIdentity: Codable, Sendable, Equatable {
    public let device: Int64
    public let inode: UInt64
    public let mode: UInt32
    public let size: Int64
    public let modifiedSeconds: Int64
    public let modifiedNanoseconds: Int64
    public let changedSeconds: Int64
    public let changedNanoseconds: Int64
    init(_ info: stat) {
        device = Int64(info.st_dev); inode = UInt64(info.st_ino); mode = UInt32(info.st_mode)
        size = Int64(info.st_size)
        modifiedSeconds = Int64(info.st_mtimespec.tv_sec); modifiedNanoseconds = Int64(info.st_mtimespec.tv_nsec)
        changedSeconds = Int64(info.st_ctimespec.tv_sec); changedNanoseconds = Int64(info.st_ctimespec.tv_nsec)
    }
    var isDirectory: Bool { mode & UInt32(S_IFMT) == UInt32(S_IFDIR) }
    var isRegular: Bool { mode & UInt32(S_IFMT) == UInt32(S_IFREG) }
    // Ancestor directories can change contents without changing the chain's
    // object identity. Selected objects themselves require full equality.
    func sameObject(as other: Self) -> Bool { device == other.device && inode == other.inode && mode == other.mode }
}
public struct InventoryPathIdentity: Codable, Sendable, Equatable {
    public let path: String
    public let identity: FileIdentity
    init(path: String, identity: FileIdentity) { self.path = path; self.identity = identity }
}

enum FileIdentityReader {
    static func canonicalDirectoryPath(_ path: String) throws -> String {
        guard let resolved = realpath(path, nil) else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    static func rootPathWithoutFollowingLeaf(_ url: URL) throws -> String {
        guard url.isFileURL, let path = InventoryPaths.normalized(url.path) else { throw CoreError.invalidRoot }
        if path == "/" { return path }
        let parent = try canonicalDirectoryPath(InventoryPaths.parent(path))
        guard let leaf = path.split(separator: "/").last else { throw CoreError.invalidRoot }
        return (parent == "/" ? "" : parent) + "/" + leaf
    }

    static func at(_ path: String) throws -> FileIdentity {
        var info = stat()
        guard lstat(path, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let identity = FileIdentity(info)
        guard identity.isDirectory || identity.isRegular else { throw CocoaError(.fileReadUnsupportedScheme) }
        return identity
    }
    // Walk from '/' using descriptor-relative no-follow opens. A root reached
    // through symlinked ancestors may be scanned but is ineligible for Trash.
    static func rootChain(_ path: String) throws -> [InventoryPathIdentity] {
        guard InventoryPaths.normalized(path) == path else { throw InventoryNavigationError.outsideScope }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var result = [InventoryPathIdentity(path: "/", identity: FileIdentity(info))]
        var current = ""
        for component in path.split(separator: "/") {
            let name = String(component)
            let next = openat(fd, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            close(fd); fd = next; current += "/" + name
            guard fstat(fd, &info) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            result.append(InventoryPathIdentity(path: current, identity: FileIdentity(info)))
        }
        return result
    }
}
