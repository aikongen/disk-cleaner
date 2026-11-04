import Foundation

public enum Coverage: String, Codable, Sendable { case complete, partial, unavailable }
public struct VolumeCapacity: Codable, Sendable {
    public let totalBytes: Int64
    public let availableBytes: Int64
    public init(totalBytes: Int64, availableBytes: Int64) { self.totalBytes = totalBytes; self.availableBytes = availableBytes }
}
public struct InventoryEntry: Codable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let name: String
    public let apparentBytes: Int64
    public let allocatedBytes: Int64?
    public let modifiedAt: Date?
    public let isDirectory: Bool
    public let coverage: Coverage
    public let identity: FileIdentity?
    public var knownApparentBytes: Int64? { coverage == .unavailable ? nil : apparentBytes }
    public init(path: String, name: String, apparentBytes: Int64, allocatedBytes: Int64?, modifiedAt: Date?, isDirectory: Bool, coverage: Coverage, identity: FileIdentity? = nil) { self.path = path; self.name = name; self.apparentBytes = apparentBytes; self.allocatedBytes = allocatedBytes; self.modifiedAt = modifiedAt; self.isDirectory = isDirectory; self.coverage = coverage; self.identity = identity }
}
public struct InventorySnapshot: Codable, Sendable, Identifiable {
    public let id: UUID
    public let root: String
    public let createdAt: Date
    public let entries: [InventoryEntry]
    public let errors: [String]
    public let capacity: VolumeCapacity?
    // Optional for backwards decoding: older scans cannot establish comparable scope.
    public let scannerVersion: Int?
    public let volumeUUID: String?
    public let rootDevice: Int64?
    public let rootInode: UInt64?
    public let rootIdentity: FileIdentity?
    public let rootAncestors: [InventoryPathIdentity]?
    public let invalidatedAt: Date?
    public var isStale: Bool { invalidatedAt != nil }
    public init(id: UUID = UUID(), root: String, createdAt: Date = Date(), entries: [InventoryEntry], errors: [String], capacity: VolumeCapacity?, scannerVersion: Int? = nil, volumeUUID: String? = nil, rootDevice: Int64? = nil, rootInode: UInt64? = nil, rootIdentity: FileIdentity? = nil, rootAncestors: [InventoryPathIdentity]? = nil, invalidatedAt: Date? = nil) { self.id = id; self.root = root; self.createdAt = createdAt; self.entries = entries; self.errors = errors; self.capacity = capacity; self.scannerVersion = scannerVersion; self.volumeUUID = volumeUUID; self.rootDevice = rootDevice; self.rootInode = rootInode; self.rootIdentity = rootIdentity; self.rootAncestors = rootAncestors; self.invalidatedAt = invalidatedAt }
}
public enum JobStatus: String, Codable, Sendable { case queued, running, completed, insufficient, failed, interrupted }
public struct CleanupJob: Codable, Sendable, Identifiable {
    public let id: UUID
    public let key: String
    public let targetBytes: Int64
    public var status: JobStatus
    public let createdAt: Date
    public var beforeBytes: Int64?
    public var afterBytes: Int64?
    public var message: String
    public var requester: String = "Disk Cleaner"
    public init(id: UUID = UUID(), key: String, targetBytes: Int64, status: JobStatus, createdAt: Date = Date(), beforeBytes: Int64? = nil, afterBytes: Int64? = nil, message: String, requester: String = "Disk Cleaner") { self.id = id; self.key = key; self.targetBytes = targetBytes; self.status = status; self.createdAt = createdAt; self.beforeBytes = beforeBytes; self.afterBytes = afterBytes; self.message = message; self.requester = requester }
}
public enum CoreError: Error, LocalizedError {
    case invalidRequest, idempotencyConflict, missingJob, invalidRoot
    public var errorDescription: String? {
        switch self { case .invalidRequest: "Invalid request"; case .idempotencyConflict: "Idempotency key already used for another target"; case .missingJob: "Job not found"; case .invalidRoot: "Root is not a readable directory" }
    }
}
public enum DataLocation {
    public static func applicationSupport() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DiskCleaner", isDirectory: true)
    }
}
