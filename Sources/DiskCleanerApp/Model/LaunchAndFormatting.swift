import Foundation

// Pure launch and formatting helpers. No SwiftUI or AppKit, so the fixture
// tests compile these exact sources.

enum Screen: String, CaseIterable, Sendable {
    case overview, browse, cleanups
    var title: String { switch self { case .overview: "Overview"; case .browse: "Browse files"; case .cleanups: "Cleanups" } }
}

enum BrowseStage: Equatable, Sendable { case list, review, outcome }

/// Every fixture scene that the preview can open directly.
enum FixtureScene: String, CaseIterable, Sendable {
    case overview, browse
    case browseTree = "browse-tree"
    case empty, scanning, settings
    case browseEmpty = "browse-empty"
    case cleanupsEmpty = "cleanups-empty"
    case trashReview = "trash-review"
    case trashOutcome = "trash-outcome"
    case cleanupResult = "cleanup-result"
}

enum LaunchOptions {
    /// Fixture mode is fixed at launch. Nothing in the running app can turn it off.
    static func isFixture(arguments: [String], environment: [String: String], bundleDemoMode: Bool) -> Bool {
        bundleDemoMode || arguments.contains("--demo") || environment["DISK_CLEANER_DEMO"] == "1"
    }
    /// `--scene <name>` wins over `DISK_CLEANER_SCENE`. Unknown names are ignored.
    static func scene(arguments: [String], environment: [String: String]) -> FixtureScene? {
        if let index = arguments.firstIndex(of: "--scene"), arguments.indices.contains(index + 1),
           let scene = FixtureScene(rawValue: arguments[index + 1]) { return scene }
        if let value = environment["DISK_CLEANER_SCENE"], let scene = FixtureScene(rawValue: value) { return scene }
        return nil
    }
}

func bytes(_ value: Int64?) -> String {
    guard let value else { return "Unknown" }
    if abs(value) >= 1_000_000_000 { return value.isMultiple(of: 1_000_000_000) ? "\(value / 1_000_000_000) GB" : String(format: "%.1f GB", Double(value) / 1_000_000_000) }
    return ByteCountFormatter.string(fromByteCount: value, countStyle: .decimal)
}

func dateText(_ date: Date?, time: Bool = false) -> String {
    guard let date else { return "Not recorded" }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_GB")
    formatter.dateFormat = time ? "d MMM, HH:mm" : "d MMM yyyy"
    return formatter.string(from: date)
}

/// Free space on the boot volume for the no-scan Overview. The preview shows an example figure.
struct BootVolumeFigure: Equatable, Sendable {
    let name: String
    let availableBytes: Int64
    static let example = BootVolumeFigure(name: "Macintosh HD", availableBytes: 312_000_000_000)
    var availableText: String { "\(Int((Double(availableBytes) / 1_000_000_000).rounded())) GB" }
    static func measure() -> BootVolumeFigure? {
        let url = URL(fileURLWithPath: "/")
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: url.path),
              let free = attributes[.systemFreeSize] as? NSNumber else { return nil }
        let name = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName ?? "this Mac"
        return BootVolumeFigure(name: name, availableBytes: free.int64Value)
    }
}
