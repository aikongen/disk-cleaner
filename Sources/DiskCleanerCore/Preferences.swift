import Foundation

public enum SnapshotRetention: Int, Codable, Sendable, CaseIterable { case five = 5, ten = 10, thirty = 30 }
public struct UserPreferences: Codable, Sendable, Equatable {
    public var rememberLastScan: Bool
    public var retention: SnapshotRetention
    public init(rememberLastScan: Bool = true, retention: SnapshotRetention = .thirty) {
        self.rememberLastScan = rememberLastScan; self.retention = retention
    }
}
private struct PreferencesLedger: Codable { var version = 1; var preferences = UserPreferences() }
public enum PreferencesError: Error, LocalizedError {
    case unsupportedVersion
    public var errorDescription: String? { "These settings were saved by an unsupported version. The original file was kept." }
}
public actor PreferencesStore {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func load(defaults: UserPreferences = UserPreferences()) throws -> UserPreferences {
        try DiskFile(directory: directory, name: "preferences.json", fallback: PreferencesLedger(preferences: defaults)).read {
            guard $0.version == 1 else { throw PreferencesError.unsupportedVersion }
            return $0.preferences
        }
    }
    public func save(_ preferences: UserPreferences) throws {
        try StoreOperationLock.withExclusive(directory: directory) {
            try DiskFile(directory: directory, name: "preferences.json", fallback: PreferencesLedger()).locked {
                guard $0.version == 1 else { throw PreferencesError.unsupportedVersion }
                $0.preferences = preferences
            }
        }
    }
}

public enum InventoryOperationError: Error, LocalizedError {
    case busy
    public var errorDescription: String? { "A scan or file action is still running. Wait for it to finish." }
}
// All normal stores/services share this process gate. An async scan yields its
// actor but retains the gate; a concurrent scan or manual file action fails busy.
public actor InventoryOperationGate {
    public static let shared = InventoryOperationGate()
    public init() {}
    func perform<T: Sendable>(key: String, _ operation: @Sendable () async throws -> T) async throws -> T {
        let lease = try StoreOperationLock.acquire(directory: URL(fileURLWithPath: key))
        defer { StoreOperationLock.release(lease.descriptor) }
        return try await operation()
    }
}
