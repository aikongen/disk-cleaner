import Foundation
import DiskCleanerCore

/// Example inventory for the fixture preview. Paths are invented under
/// /Users/example; nothing here is read from, or written to, the disk.
enum FixtureData {
    static let gb: Int64 = 1_000_000_000
    static let root = "/Users/example"
    static let snapshotID = UUID(uuidString: "6E0C5A51-8D0E-4E36-9C55-7A3D0F2B1F15")!
    static let olderPreviews = "/Users/example/Developer/Chief/Older previews"
    static let installers = "/Users/example/Downloads/Installers"
    /// Reported as changed since the scan in the example outcome.
    static let changedSinceScan: Set<String> = [installers]

    static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value) ?? .distantPast }
    static let scanDate = date("2026-11-04T10:20:00+01:00")
    static let comparisonDate = date("2026-11-03T10:20:00+01:00")

    private static func entry(_ relative: String, _ name: String? = nil, _ size: Int64, directory: Bool = true, coverage: Coverage = .complete, modified: String? = nil) -> InventoryEntry {
        let path = root + "/" + relative
        return InventoryEntry(path: path, name: name ?? URL(fileURLWithPath: path).lastPathComponent, apparentBytes: size,
                              allocatedBytes: coverage == .complete ? size : nil, modifiedAt: modified.map(date), isDirectory: directory, coverage: coverage)
    }

    static let snapshot: InventorySnapshot = {
        let g = gb
        let entries: [InventoryEntry] = [
            entry("Documents", nil, 126 * g, coverage: .partial, modified: "2026-11-01T12:00:00+01:00"),
            entry("Documents/Projects", nil, 84 * g, modified: "2026-11-01T12:00:00+01:00"),
            entry("Documents/Scans", nil, 42 * g, coverage: .partial, modified: "2026-10-28T09:00:00+01:00"),
            entry("Pictures", "Photos", 98 * g, modified: "2026-10-30T18:00:00+01:00"),
            entry("Pictures/Photos Library.photoslibrary", "Photos Library", 98 * g, modified: "2026-10-30T18:00:00+01:00"),
            entry("Applications", nil, 76 * g, modified: "2026-10-15T08:00:00+02:00"),
            entry("Developer", nil, 61 * g, coverage: .partial, modified: "2026-11-03T16:00:00+01:00"),
            entry("Developer/Chief", nil, 27_300_000_000, coverage: .partial, modified: "2026-11-03T16:00:00+01:00"),
            entry("Developer/Chief/Older previews", "Chief older previews", 2_300_000_000, modified: "2026-10-10T12:00:00+02:00"),
            entry("Developer/Chief/Build data", nil, 25 * g, modified: "2026-11-03T16:00:00+01:00"),
            entry("Developer/Package cache", nil, 15 * g, modified: "2026-11-04T09:00:00+01:00"),
            entry("Developer/Preview builds", nil, 3_800_000_000, modified: "2026-11-02T11:00:00+01:00"),
            entry("Downloads", nil, 9_400_000_000, coverage: .partial, modified: "2026-11-02T14:00:00+01:00"),
            entry("Downloads/Installers", "Installers in Downloads", 4_100_000_000, modified: "2026-08-22T12:00:00+02:00"),
            entry("Downloads/Xcode_27.xip", nil, 3_200_000_000, directory: false, modified: "2026-09-20T10:00:00+02:00"),
            entry("Downloads/Shared", nil, 2_100_000_000, coverage: .partial, modified: "2026-10-05T10:00:00+02:00"),
            entry("Movies", nil, 0, coverage: .unavailable, modified: nil),
        ]
        return InventorySnapshot(id: snapshotID, root: root, createdAt: scanDate, entries: entries,
                                 errors: ["/Users/example/Movies: permission denied (example)"],
                                 capacity: VolumeCapacity(totalBytes: 500 * g, availableBytes: 18 * g))
    }()

    /// Overview categories: example figures, not derived from the snapshot.
    static let categories: [FileItem] = {
        let g = gb
        return [
            FileItem(path: "category:developer", name: "Developer files", bytes: 61 * g, modified: nil, coverage: .complete, hue: 0, directory: false),
            FileItem(path: "category:applications", name: "Applications", bytes: 76 * g, modified: nil, coverage: .complete, hue: 1, directory: false),
            FileItem(path: "category:documents", name: "Documents", bytes: 126 * g, modified: nil, coverage: .partial, hue: 2, directory: false),
            FileItem(path: "category:photos", name: "Photos", bytes: 98 * g, modified: nil, coverage: .complete, hue: 3, directory: false),
            FileItem(path: "category:other", name: "Other scanned files", bytes: 109 * g, modified: nil, coverage: .complete, hue: 4, directory: false),
        ]
    }()

    static let jobs: [PresentedJob] = [
        PresentedJob(id: "1024", date: date("2026-11-04T10:24:00+01:00"), requester: "Codex agent", status: "insufficient", goal: 24 * gb, before: 18 * gb, after: 22_100_000_000, message: "No further automatic cleanup was available for this request.", demoEstimate: true),
        PresentedJob(id: "0842", date: date("2026-11-04T08:42:00+01:00"), requester: "Codex agent", status: "completed", goal: 18 * gb, before: 12_100_000_000, after: 18 * gb, message: ""),
    ]
}
