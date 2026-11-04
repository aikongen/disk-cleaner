import Foundation
import Testing
@testable import DiskCleanerCore
#if canImport(DiskCleanerApp)
@testable import DiskCleanerApp
#endif

// App view-model fixtures. SwiftPM imports the app module; the Xcode wrapper
// compiles the same Model/*.swift sources into this test bundle. Every
// filesystem path used here is a generated temporary folder or an invented
// /Users/example path; nothing scans or moves personal data.

private func temporaryFolder() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("DiskCleanerAppModelTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url.resolvingSymlinksInPath()
}

@MainActor
private func waitFor(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<2000 where !condition() { try? await Task.sleep(for: .milliseconds(5)) }
}

@Test func launchOptionsSelectScenesAndFixtureModeOnce() {
    #expect(LaunchOptions.scene(arguments: ["app", "--scene", "trash-outcome"], environment: [:]) == .trashOutcome)
    #expect(LaunchOptions.scene(arguments: ["app"], environment: ["DISK_CLEANER_SCENE": "browse-tree"]) == .browseTree)
    #expect(LaunchOptions.scene(arguments: ["app", "--scene", "browse"], environment: ["DISK_CLEANER_SCENE": "empty"]) == .browse)
    #expect(LaunchOptions.scene(arguments: ["app", "--scene", "nonsense"], environment: [:]) == nil)
    #expect(LaunchOptions.isFixture(arguments: ["app", "--demo"], environment: [:], bundleDemoMode: false))
    #expect(LaunchOptions.isFixture(arguments: ["app"], environment: ["DISK_CLEANER_DEMO": "1"], bundleDemoMode: false))
    #expect(LaunchOptions.isFixture(arguments: ["app"], environment: [:], bundleDemoMode: true))
    #expect(!LaunchOptions.isFixture(arguments: ["app"], environment: [:], bundleDemoMode: false))
    #expect(Set(FixtureScene.allCases.map(\.rawValue)) == ["overview", "browse", "browse-tree", "empty", "browse-empty", "cleanups-empty", "scanning", "settings", "trash-review", "trash-outcome", "cleanup-result"])
}

@MainActor @Test func selectionStaysSeparateFromNavigation() throws {
    let model = CleanerModel(isFixture: true)
    let downloads = FixtureData.root + "/Downloads"
    #expect(model.currentPath == FixtureData.root)
    let folder = try #require(model.visibleItems.first { $0.path == downloads })
    model.open(folder)
    #expect(model.currentPath == downloads)
    #expect(model.checkedPaths.isEmpty)
    #expect(model.selectedItem == downloads)
    #expect(model.breadcrumbs.map(\.path) == [FixtureData.root, downloads])
    #expect(model.canGoBack)

    model.toggleChecked(FixtureData.installers)
    #expect(model.checkedPaths == [FixtureData.installers])
    #expect(model.currentPath == downloads)
    #expect(model.checkedTotal == 4_100_000_000)

    // Partial-coverage folders cannot be checked and never show a folder total.
    let shared = try #require(model.visibleItems.first { $0.name == "Shared" })
    #expect(shared.sizeHidden)
    model.toggleChecked(shared.path)
    #expect(!model.checkedPaths.contains(shared.path))

    model.back()
    #expect(model.currentPath == FixtureData.root)
    #expect(model.scrollTarget == downloads)
    #expect(model.selectedItem == downloads)
    #expect(model.checkedPaths == [FixtureData.installers])
    #expect(!model.canGoBack)

    model.search = "installers"
    #expect(model.visibleItems.map(\.path) == [FixtureData.installers])
    model.clearChecks()
    #expect(model.checkedPaths.isEmpty)
}

@MainActor @Test func fixtureTrashFlowMarksOnlyAndNeverTouchesFiles() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("keep.bin")
    try Data(repeating: 7, count: 64).write(to: file)
    let snapshot = InventorySnapshot(root: folder.path, entries: [
        InventoryEntry(path: file.path, name: "keep.bin", apparentBytes: 64, allocatedBytes: 64, modifiedAt: Date(), isDirectory: false, coverage: .complete)
    ], errors: [], capacity: nil)
    let flow = FixtureTrashFlow()
    let review = try await flow.review(snapshot: snapshot, paths: [file.path])
    #expect(review.items.map(\.path) == [file.path])
    let outcome = try await flow.execute(reviewID: review.id)
    #expect(outcome.items.map(\.status) == [.moved])
    #expect(outcome.requiresRescan)
    #expect(flow.markedPaths == [file.path])
    #expect(FileManager.default.fileExists(atPath: file.path))
    #expect(try Data(contentsOf: file).count == 64)
    await #expect(throws: FixtureTrashError.reviewUnavailable) { try await flow.execute(reviewID: review.id) }
    await #expect(throws: FixtureTrashError.rootSelection) { try await flow.review(snapshot: snapshot, paths: [folder.path]) }
}

@MainActor @Test func fixtureReviewAndConfirmRunThroughTheFixtureFlow() async throws {
    let model = CleanerModel(isFixture: true)
    #expect(model.trashIsExample)
    #expect(model.confirmHeldReason == nil)
    #expect(!model.usesLiveTrash)
    model.toggleChecked(FixtureData.olderPreviews)
    model.toggleChecked(FixtureData.installers)
    model.requestTrashReview()
    await waitFor { model.browseStage == .review }
    let review = try #require(model.review)
    #expect(review.items.map(\.path) == [FixtureData.olderPreviews, FixtureData.installers])
    #expect(review.totalBytes == 6_400_000_000)
    #expect(model.canConfirmTrash)
    model.confirmTrash()
    await waitFor { model.browseStage == .outcome }
    let outcome = try #require(model.outcome)
    #expect(outcome.movedCount == 1)
    #expect(outcome.items.first { $0.path == FixtureData.installers }?.status == .notMoved)
    #expect(outcome.requiresRescan)
    #expect(model.stale)
    #expect(!model.canCheckForTrash)
    #expect(model.checkedPaths == [FixtureData.installers])
    #expect(!model.visibleItems.contains { $0.path == FixtureData.root + "/Developer/Chief/Older previews" })
}

@MainActor @Test func normalAppPreferencesRoundTrip() async throws {
    let folder = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let model = CleanerModel(isFixture: false, storageDirectory: folder, trashFlow: LiveTrashFlow(directory: folder, makeConfirmedBackend: { RefusingRecordingBackend(RecordingFactory()) }))
    await model.waitUntilLoaded()
    #expect(model.settingsLoaded)
    #expect(model.preferences == CleanerModel.firstLaunchPreferences)
    #expect(model.scanControlsDisabledReason == nil)
    #expect(!model.hasSnapshot)

    model.setPreference(\.rememberLastScan, to: false)
    model.setPreference(\.retention, to: .five)
    await model.waitUntilLoaded()
    let stored = try await PreferencesStore(directory: folder).load(defaults: CleanerModel.firstLaunchPreferences)
    #expect(stored == UserPreferences(rememberLastScan: false, retention: .five))

    let reopened = CleanerModel(isFixture: false, storageDirectory: folder, trashFlow: FixtureTrashFlow())
    await reopened.waitUntilLoaded()
    #expect(reopened.preferences.retention == .five)
}

/// Counts every backend the confirm path asks for. Its backend refuses each move.
private final class RecordingFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var madeCount = 0
    private var targets: [String] = []
    var made: Int { lock.withLock { madeCount } }
    var attempted: [String] { lock.withLock { targets } }
    func make() { lock.withLock { madeCount += 1 } }
    func record(_ path: String) { lock.withLock { targets.append(path) } }
}
private struct RefusingRecordingBackend: TrashBackend {
    let factory: RecordingFactory
    init(_ factory: RecordingFactory) { self.factory = factory }
    func moveToTrash(_ target: TrashTarget, validate: () throws -> Void) throws -> URL {
        factory.record(target.path)
        throw CocoaError(.featureUnsupported)
    }
}

@MainActor @Test func normalAppBuildsTheRealBackendOnlyFromConfirm() async throws {
    // Type-level: the app's single construction site yields SystemTrashBackend.
    // Constructing it performs no filesystem access; it is never called here.
    #expect(LiveTrashFlow.makeSystemBackend() is SystemTrashBackend)

    let store = try temporaryFolder(), scanned = try temporaryFolder()
    defer { try? FileManager.default.removeItem(at: store); try? FileManager.default.removeItem(at: scanned) }
    let file = scanned.appendingPathComponent("generated.bin")
    try Data(repeating: 3, count: 128).write(to: file)

    let factory = RecordingFactory()
    let flow = LiveTrashFlow(directory: store, makeConfirmedBackend: { factory.make(); return RefusingRecordingBackend(factory) })
    let model = CleanerModel(isFixture: false, storageDirectory: store, trashFlow: flow)
    await model.waitUntilLoaded()
    #expect(model.usesLiveTrash)
    model.beginChosenScan(scanned)
    await waitFor { !model.scanning && model.hasSnapshot }
    let row = try #require(model.visibleItems.first { $0.name == "generated.bin" })
    model.open(row)
    model.toggleChecked(row.path)
    #expect(model.checkedPaths == [row.path])
    #expect(factory.made == 0)

    model.requestTrashReview()
    await waitFor { model.browseStage == .review || model.error != nil }
    #expect(model.error == nil)
    #expect(model.review?.items.map(\.path) == [row.path])
    #expect(factory.made == 0)
    #expect(!flow.isArmed)
    #expect(model.canConfirmTrash)

    model.cancelReview()
    #expect(factory.made == 0)
    model.requestTrashReview()
    await waitFor { model.browseStage == .review }
    model.confirmTrash()
    await waitFor { model.browseStage == .outcome || model.error != nil }
    #expect(factory.made == 1)
    #expect(factory.attempted == [row.path])
    #expect(!flow.isArmed)
    let outcome = try #require(model.outcome)
    #expect(outcome.items.allSatisfy { $0.status != .moved })
    #expect(outcome.requiresRescan)
    #expect(model.stale)
    #expect(FileManager.default.fileExists(atPath: file.path))
}

@MainActor @Test func fixtureWiringNeverReachesTheRealBackend() async throws {
    let model = CleanerModel(isFixture: true, scene: .trashReview)
    #expect(!model.usesLiveTrash)
    #expect(model.trashIsExample)
    model.confirmTrash()
    await waitFor { model.browseStage == .outcome }
    #expect(model.outcome?.items.count == 2)
    #expect(!model.usesLiveTrash)
}

@MainActor @Test func fixtureModeCannotScanAndKeepsSettingsInMemory() throws {
    let model = CleanerModel(isFixture: true)
    #expect(model.scanControlsDisabledReason != nil)
    model.beginChosenScan(FileManager.default.temporaryDirectory)
    model.rescan()
    #expect(!model.scanning)
    #expect(model.root?.path == FixtureData.root)
    #expect(model.storageDirectory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    #expect(!FileManager.default.fileExists(atPath: model.storageDirectory.path))
}

@MainActor @Test func everyFixtureSceneLoads() throws {
    for scene in FixtureScene.allCases {
        let model = CleanerModel(isFixture: true, scene: scene)
        #expect(model.initialScene == scene)
        switch scene {
        case .overview:
            #expect(model.screen == .overview); #expect(model.hasSnapshot); #expect(!model.settingsOpen)
        case .settings:
            #expect(model.screen == .overview); #expect(model.hasSnapshot); #expect(model.settingsOpen)
        case .browse:
            #expect(model.screen == .browse); #expect(model.atRoot); #expect(model.selected?.name == "Documents")
        case .browseTree:
            #expect(model.currentPath == FixtureData.root + "/Downloads"); #expect(model.checkedPaths.count == 2)
            #expect(model.selected?.path == FixtureData.installers)
        case .empty:
            #expect(!model.hasSnapshot); #expect(model.scanDate == nil)
        case .browseEmpty:
            #expect(!model.hasSnapshot); #expect(model.screen == .browse)
        case .cleanupsEmpty:
            #expect(!model.hasSnapshot); #expect(model.screen == .cleanups); #expect(model.job == nil)
        case .scanning:
            #expect(model.scanning); #expect(model.previousSnapshotAvailable)
            model.cancelScan(); #expect(!model.scanning)
        case .trashReview:
            #expect(model.browseStage == .review); #expect(model.review?.items.count == 2)
        case .trashOutcome:
            #expect(model.browseStage == .outcome); #expect(model.outcome?.movedCount == 1); #expect(model.outcome?.items.count == 2)
            #expect(model.outcome?.requiresRescan == true)
        case .cleanupResult:
            #expect(model.screen == .cleanups); #expect(model.job?.id == "1024")
        }
    }
}

/// Motion direction follows travel: deeper, back and breadcrumb jumps report
/// the side new content arrives from; reversing flips it.
@MainActor @Test func navigationStepFollowsDirectionOfTravel() throws {
    let model = CleanerModel(isFixture: true)
    let downloads = FixtureData.root + "/Downloads"
    let folder = try #require(model.visibleItems.first { $0.path == downloads })
    model.open(folder)
    #expect(model.navigationStep == 1)
    model.back()
    #expect(model.navigationStep == -1)
    model.open(folder)
    #expect(model.navigationStep == 1)
    model.navigate(FixtureData.root)
    #expect(model.navigationStep == -1)
    model.navigate(FixtureData.root)
    #expect(model.navigationStep == 0)
}

/// Settings is a page in the main window: opening it keeps the page below untouched,
/// Back returns to exactly that page, and a tab click closes it.
@MainActor @Test func settingsPageReturnsToTheExactPreviousPage() throws {
    let model = CleanerModel(isFixture: true, scene: .browseTree)
    let path = model.currentPath, selected = model.selectedItem, checks = model.checkedPaths, count = model.navigationCount
    model.openSettingsPage()
    #expect(model.settingsOpen)
    model.setPreference(\.rememberLastScan, to: false)
    #expect(!model.preferences.rememberLastScan)
    model.closeSettingsPage()
    #expect(!model.settingsOpen)
    #expect(model.screen == .browse && model.currentPath == path && model.selectedItem == selected && model.checkedPaths == checks)
    #expect(model.navigationCount == count)
    model.toggleSettingsPage(); model.show(.cleanups)
    #expect(!model.settingsOpen && model.screen == .cleanups)
}

/// Cancel in the Trash review returns to the list exactly as it was: same folder,
/// inspected row and checks, and no scroll command is issued (the list stays laid out and
/// unscrolled under the review, so its position cannot change).
@MainActor @Test func cancelReviewRestoresTheListContext() async throws {
    let model = CleanerModel(isFixture: true, scene: .browseTree)
    let path = model.currentPath, selected = model.selectedItem, checks = model.checkedPaths
    let count = model.navigationCount, target = model.scrollTarget
    model.requestTrashReview()
    await waitFor { model.browseStage == .review }
    model.cancelReview()
    #expect(model.browseStage == .list)
    #expect(model.currentPath == path && model.selectedItem == selected && model.checkedPaths == checks)
    #expect(model.navigationCount == count && model.scrollTarget == target)
}

/// A jump from Overview is lateral (the page fade is the cue) and marks the row to locate.
@MainActor @Test func revealFromOverviewIsLateralAndMarksTheRow() throws {
    let model = CleanerModel(isFixture: true)
    model.reveal(inBrowse: FixtureData.installers)
    #expect(model.screen == .browse && model.navigationStep == 0)
    #expect(model.revealedPath == FixtureData.installers && model.revealCount == 1)
    #expect(model.selectedItem == FixtureData.installers && model.scrollTarget == FixtureData.installers)
}

/// While the Trash review holds the list column, every navigation path is inert: the
/// breadcrumb, back, a row or the inspector's Open folder, and a jump from Overview. The
/// jump still lands on the open review. Cancel then returns to the exact folder and row.
@MainActor @Test func navigationIsInertDuringTheReview() async throws {
    let model = CleanerModel(isFixture: true, scene: .browseTree)
    let path = model.currentPath, selected = model.selectedItem, checks = model.checkedPaths
    let count = model.navigationCount, target = model.scrollTarget
    model.requestTrashReview()
    await waitFor { model.browseStage == .review }
    #expect(!model.listNavigable)
    model.navigate(FixtureData.root)
    model.back()
    if let folder = model.visibleItems.first(where: { $0.directory }) { model.open(folder) }
    model.show(.overview)
    model.reveal(inBrowse: FixtureData.olderPreviews)
    #expect(model.screen == .browse && model.browseStage == .review)
    #expect(model.currentPath == path && model.selectedItem == selected && model.navigationCount == count)
    #expect(model.revealedPath == nil && model.scrollTarget == target)
    model.cancelReview()
    #expect(model.listNavigable && model.currentPath == path && model.selectedItem == selected && model.checkedPaths == checks)
}

/// Leaving Settings by a tab is marked, so the tab highlight fades in at its destination
/// instead of sliding; an ordinary tab change slides as before.
@MainActor @Test func leavingSettingsByATabIsMarked() throws {
    let model = CleanerModel(isFixture: true)
    model.openSettingsPage()
    model.show(.browse)
    #expect(!model.settingsOpen && model.screen == .browse && model.pageChangeLeftSettings)
    model.show(.cleanups)
    #expect(model.screen == .cleanups && !model.pageChangeLeftSettings)
}

/// A jump from Overview swaps the folder together with the page; ordinary navigation
/// afterwards fades the rows again.
@MainActor @Test func revealArrivesWithThePage() throws {
    let model = CleanerModel(isFixture: true)
    model.reveal(inBrowse: FixtureData.installers)
    #expect(model.folderArrivesWithPage)
    model.back()
    #expect(!model.folderArrivesWithPage)
}

#if canImport(DiskCleanerApp)
@Suite struct AboutWhatsNewTests {
    private let log = """
    # Changelog

    ## Unreleased

    - Unreleased item.

    ## 0.2.0 - 2026-12-01

    ### Added

    - First `0.2.0` item.
    - Second item.

    ## 0.1.0 - 2026-11-04

    - Only 0.1.0 item.
    """
    @Test func picksTheFirstBulletOfTheMatchingVersion() {
        #expect(AboutWhatsNew.line(for: "0.2.0", in: log) == "First 0.2.0 item.")
        #expect(AboutWhatsNew.line(for: "0.1.0", in: log) == "Only 0.1.0 item.")
    }
    @Test func hidesTheLineWhenTheVersionHasNoSection() {
        #expect(AboutWhatsNew.line(for: "0.3.0", in: log) == nil)
        #expect(AboutWhatsNew.line(for: "0.2", in: log) == nil)
    }
}
#endif
