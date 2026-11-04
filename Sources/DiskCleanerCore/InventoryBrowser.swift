import Foundation

public enum InventorySort: String, Codable, Sendable, CaseIterable { case name, size, modified }
public enum InventorySortDirection: String, Codable, Sendable { case ascending, descending }
public struct InventoryBreadcrumb: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public let path: String
    public let name: String
}
public struct InventoryDirectorySummary: Sendable {
    // Recorded apparent bytes are an estimate of the known subset, never gain.
    public let recordedApparentBytes: Int64?
    public let allocatedBytes: Int64?
    public let hasCoverageGaps: Bool
}
public enum InventoryNavigationError: Error, LocalizedError {
    case invalidSnapshot, outsideScope, notDirectory
    public var errorDescription: String? {
        switch self {
        case .invalidSnapshot: "The saved inventory contains invalid or duplicate paths. Scan this folder again."
        case .outsideScope: "This path is outside the saved scan."
        case .notDirectory: "This folder is not recorded in the saved scan."
        }
    }
}

// Snapshot navigation never reads or scans the filesystem.
public struct InventoryBrowser: Sendable {
    public let snapshot: InventorySnapshot
    public let rootPath: String
    private let index: [String: InventoryEntry]
    private let childrenIndex: [String: [InventoryEntry]]

    public init(snapshot: InventorySnapshot) throws {
        guard let root = InventoryPaths.normalized(snapshot.root), root == snapshot.root else { throw InventoryNavigationError.invalidSnapshot }
        var index: [String: InventoryEntry] = [:]
        var children: [String: [InventoryEntry]] = [:]
        for entry in snapshot.entries {
            guard let path = InventoryPaths.normalized(entry.path), path == entry.path,
                  InventoryPaths.contains(root: root, path: path), path != root, entry.apparentBytes >= 0,
                  entry.allocatedBytes.map({ $0 >= 0 }) ?? true,
                  index.updateValue(entry, forKey: path) == nil else { throw InventoryNavigationError.invalidSnapshot }
            children[InventoryPaths.parent(path), default: []].append(entry)
        }
        // An orphan cannot be safely presented as part of a coherent stored tree.
        for entry in snapshot.entries {
            let parent = InventoryPaths.parent(entry.path)
            guard parent == root || index[parent]?.isDirectory == true else { throw InventoryNavigationError.invalidSnapshot }
        }
        self.snapshot = snapshot; rootPath = root; self.index = index; childrenIndex = children
    }
    public func entry(at path: String) -> InventoryEntry? { index[path] }
    public func parent(of path: String) -> String? {
        guard path != rootPath, index[path] != nil else { return nil }
        let parent = InventoryPaths.parent(path)
        return InventoryPaths.contains(root: rootPath, path: parent) ? parent : nil
    }
    public func breadcrumbs(to path: String) throws -> [InventoryBreadcrumb] {
        try validateDirectory(path)
        var paths = [path]
        var cursor = path
        while cursor != rootPath { cursor = InventoryPaths.parent(cursor); paths.append(cursor) }
        return paths.reversed().map { InventoryBreadcrumb(path: $0, name: $0 == "/" ? "/" : URL(fileURLWithPath: $0).lastPathComponent) }
    }
    public func children(of path: String, search: String = "", recursive: Bool = false,
                         sort: InventorySort = .size, direction: InventorySortDirection = .descending) throws -> [InventoryEntry] {
        try validateDirectory(path)
        let candidates = recursive ? snapshot.entries.filter { $0.path != path && InventoryPaths.contains(root: path, path: $0.path) } : childrenIndex[path, default: []]
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return candidates.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.path.localizedCaseInsensitiveContains(query) }.sorted { a, b in
            let order: ComparisonResult
            switch sort {
            case .name: order = a.name.localizedStandardCompare(b.name)
            case .size:
                if a.knownApparentBytes == nil && b.knownApparentBytes != nil { return false }
                if b.knownApparentBytes == nil && a.knownApparentBytes != nil { return true }
                if let av = a.knownApparentBytes, let bv = b.knownApparentBytes { order = av == bv ? .orderedSame : av < bv ? .orderedAscending : .orderedDescending }
                else { order = .orderedSame }
            case .modified:
                if a.modifiedAt == nil && b.modifiedAt != nil { return false }
                if b.modifiedAt == nil && a.modifiedAt != nil { return true }
                if let ad = a.modifiedAt, let bd = b.modifiedAt { order = ad == bd ? .orderedSame : ad < bd ? .orderedAscending : .orderedDescending }
                else { order = .orderedSame }
            }
            if order == .orderedSame { return a.path < b.path }
            return direction == .ascending ? order == .orderedAscending : order == .orderedDescending
        }
    }
    public func summary(of path: String) throws -> InventoryDirectorySummary {
        try validateDirectory(path)
        let children = childrenIndex[path, default: []]
        let gaps = (path == rootPath ? !snapshot.errors.isEmpty : index[path]?.coverage != .complete) || children.contains { $0.coverage != .complete }
        var apparent: Int64? = 0
        var allocated: Int64? = gaps ? nil : 0
        for child in children {
            if let amount = child.knownApparentBytes { apparent = Self.add(apparent, amount) }
            allocated = child.allocatedBytes.flatMap { Self.add(allocated, $0) }
        }
        return InventoryDirectorySummary(recordedApparentBytes: apparent, allocatedBytes: allocated, hasCoverageGaps: gaps)
    }
    private static func add(_ total: Int64?, _ amount: Int64) -> Int64? {
        guard let total else { return nil }
        let (value, overflow) = total.addingReportingOverflow(amount)
        return overflow ? nil : value
    }
    private func validateDirectory(_ path: String) throws {
        guard InventoryPaths.normalized(path) == path, InventoryPaths.contains(root: rootPath, path: path) else { throw InventoryNavigationError.outsideScope }
        guard path == rootPath || index[path]?.isDirectory == true else { throw InventoryNavigationError.notDirectory }
    }
}

enum InventoryPaths {
    static func normalized(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        var components: [Substring] = []
        for component in path.split(separator: "/") {
            if component == "." { continue }
            if component == ".." { if !components.isEmpty { components.removeLast() }; continue }
            components.append(component)
        }
        return "/" + components.joined(separator: "/")
    }
    static func contains(root: String, path: String) -> Bool { path == root || (root == "/" ? path.hasPrefix("/") : path.hasPrefix(root + "/")) }
    static func parent(_ path: String) -> String { let parts = path.split(separator: "/").dropLast(); return "/" + parts.joined(separator: "/") }
}
