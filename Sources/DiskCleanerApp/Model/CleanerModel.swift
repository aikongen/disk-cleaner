import Foundation
import Combine
import DiskCleanerCore

struct FileItem: Identifiable, Sendable, Equatable {
    var id: String { path }
    let path: String
    let name: String
    /// Nil when coverage is unavailable: the size is unknown, never zero.
    let bytes: Int64?
    let modified: Date?
    let coverage: Coverage
    /// Index into the view palette; nil means no data hue.
    var hue: Int?
    var growth: Int64? = nil
    var directory: Bool

    init(path: String, name: String, bytes: Int64?, modified: Date?, coverage: Coverage, hue: Int? = nil, growth: Int64? = nil, directory: Bool) {
        self.path = path; self.name = name; self.bytes = bytes; self.modified = modified; self.coverage = coverage
        self.hue = hue; self.growth = growth; self.directory = directory
    }
    init(entry: InventoryEntry, hue: Int? = nil, growth: Int64? = nil) {
        self.init(path: entry.path, name: entry.name, bytes: entry.knownApparentBytes, modified: entry.modifiedAt, coverage: entry.coverage, hue: hue, growth: growth, directory: entry.isDirectory)
    }
    /// A folder whose recorded total would be an implied size: show no size.
    var sizeHidden: Bool { bytes == nil || (directory && coverage != .complete) }
}

struct PresentedJob: Identifiable, Sendable {
    let id: String
    let date: Date
    let requester: String
    let status: String
    let goal: Int64
    let before: Int64?
    let after: Int64?
    let message: String
    var demoEstimate = false
}

@MainActor
final class CleanerModel: ObservableObject {
    @Published var screen: Screen = .overview
    /// The Settings page covers the current page in the main window; the page below keeps
    /// its scroll and selection, so Back returns to it exactly.
    @Published private(set) var settingsOpen = false
    @Published private(set) var items: [FileItem] = []
    @Published private(set) var oldItems: [FileItem] = []
    @Published private(set) var jobs: [PresentedJob] = []
    /// The inspected row. Inspection never checks a row for Trash.
    @Published var selectedItem: String?
    @Published var selectedJob: String?
    @Published var search = ""
    @Published private(set) var scanning = false
    @Published private(set) var scanRoot: URL?
    @Published var error: String?
    @Published var notice: String?
    @Published private(set) var scanDate: Date?
    @Published private(set) var comparisonDate: Date?
    @Published private(set) var root: URL?
    @Published private(set) var total: Int64?
    @Published private(set) var available: Int64?
    @Published private(set) var coverageErrors: [String] = []
    @Published private(set) var preferences = CleanerModel.firstLaunchPreferences
    @Published private(set) var settingsLoaded = false
    @Published private(set) var currentPath: String?
    @Published private(set) var checkedPaths: Set<String> = []
    @Published var sort: InventorySort = .size
    @Published var direction: InventorySortDirection = .descending
    @Published private(set) var browseStage: BrowseStage = .list
    @Published private(set) var review: TrashReviewModel?
    @Published private(set) var outcome: TrashOutcomeModel?
    @Published private(set) var trashBusy = false
    @Published private(set) var stale = false
    /// While a scan runs, the saved scan can still be viewed.
    @Published var viewingSavedDuringScan = false
    /// Row to bring back into view after navigation; nil scrolls to the top.
    @Published private(set) var scrollTarget: String?
    @Published private(set) var navigationCount = 0
    /// Direction of the last folder change: 1 deeper, -1 toward the root, 0 sideways.
    /// Views use it only to choose the side new content arrives from.
    @Published private(set) var navigationStep = 0
    /// A row opened from Overview; Browse gives it a one-time locating cue.
    @Published private(set) var revealedPath: String?
    @Published private(set) var revealCount = 0

    static let firstLaunchPreferences = UserPreferences(appearance: .purple, rememberLastScan: true, retention: .thirty)

    let isFixture: Bool
    let initialScene: FixtureScene?
    let storageDirectory: URL
    private let preferencesStore: PreferencesStore
    private let inventory: InventoryStore?
    private let jobStore: JobStore?
    private let trashFlow: (any TrashFlow)?
    private var browser: InventoryBrowser?
    private var saved: [InventorySnapshot] = []
    private var explicitScanID: UUID?
    private var chosenRoot: String?
    private var movedPaths: Set<String> = []
    private var scanTask: Task<Void, Never>?
    private var cancelRequested = false
    private var preferencesTask: Task<Void, Never>?
    private var loadTask: Task<Void, Never>?

    /// Reads the launch environment once. Fixture mode cannot change afterwards.
    convenience init() {
        let info = ProcessInfo.processInfo
        let fixture = LaunchOptions.isFixture(arguments: info.arguments, environment: info.environment,
                                              bundleDemoMode: Bundle.main.object(forInfoDictionaryKey: "DiskCleanerDemoMode") as? Bool == true)
        self.init(isFixture: fixture, scene: fixture ? LaunchOptions.scene(arguments: info.arguments, environment: info.environment) : nil)
    }

    /// - storageDirectory: injected by tests; otherwise fixture mode uses a new
    ///   temporary folder and the normal app uses Application Support/DiskCleaner.
    init(isFixture: Bool, scene: FixtureScene? = nil, storageDirectory: URL? = nil, trashFlow: (any TrashFlow)? = nil) {
        self.isFixture = isFixture
        initialScene = isFixture ? scene : nil
        let base = storageDirectory ?? (isFixture
            ? FileManager.default.temporaryDirectory.appendingPathComponent("DiskCleaner-fixture-\(UUID().uuidString)", isDirectory: true)
            : FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DiskCleaner", isDirectory: true))
        self.storageDirectory = base
        preferencesStore = PreferencesStore(directory: base)
        if isFixture {
            // No inventory or job store exists in fixture mode: nothing can scan.
            inventory = nil; jobStore = nil
            self.trashFlow = trashFlow ?? FixtureTrashFlow(changedSinceScan: FixtureData.changedSinceScan)
            settingsLoaded = true
            loadFixture()
            if let scene { apply(scene) }
        } else {
            inventory = InventoryStore(directory: base)
            jobStore = JobStore(directory: base)
            self.trashFlow = trashFlow ?? LiveTrashFlow(directory: base)
            loadTask = Task { await self.loadSettingsAndSaved() }
        }
    }

    func waitUntilLoaded() async {
        await loadTask?.value
        await preferencesTask?.value
    }

    // MARK: Derived state

    var scopeTitle: String { isFixture ? "Macintosh HD" : root?.lastPathComponent ?? "Disk Cleaner" }
    var hasSnapshot: Bool { browser != nil || (isFixture && scanDate != nil) }
    var used: Int64? { guard let total, let available else { return nil }; return max(0, total - available) }
    var categorized: Int64 { items.reduce(0) { $0 + ($1.bytes ?? 0) } }
    var residual: Int64? { guard isFixture, let used else { return nil }; return max(0, used - categorized) }
    var trashIsExample: Bool { trashFlow?.isExample ?? false }
    /// True only in the normal app: the flow that can construct SystemTrashBackend on confirm.
    var usesLiveTrash: Bool { trashFlow is LiveTrashFlow }
    var confirmHeldReason: String? { trashFlow?.confirmHeldReason }
    var job: PresentedJob? { jobs.first { $0.id == selectedJob } ?? jobs.first }
    var previousSnapshotAvailable: Bool { scanDate != nil }

    var scanControlsDisabledReason: String? {
        if isFixture { return "Example data: choosing a folder and scanning again are off in this preview." }
        if !settingsLoaded { return "Loading settings…" }
        if trashBusy || browseStage != .list { return "Finish the Trash review first." }
        return nil
    }
    /// The reason shown as a line under the scan controls. The Trash-review reason is left out
    /// (it stays on the buttons' help), so opening the review never changes the header height.
    var scanControlsStandingReason: String? {
        if isFixture { return scanControlsDisabledReason }
        return settingsLoaded ? nil : "Loading settings…"
    }

    func displayName(_ path: String) -> String {
        if isFixture && path == FixtureData.root { return "Home" }
        if path == browser?.rootPath { return root?.lastPathComponent ?? path }
        return browser?.entry(at: path)?.name ?? URL(fileURLWithPath: path).lastPathComponent
    }

    var breadcrumbs: [InventoryBreadcrumb] {
        guard let browser, let currentPath else { return [] }
        return (try? browser.breadcrumbs(to: currentPath)) ?? []
    }
    var canGoBack: Bool { guard let currentPath else { return false }; return browser?.parent(of: currentPath) != nil }
    var atRoot: Bool { currentPath != nil && currentPath == browser?.rootPath }

    /// Children of the current folder; a search looks through every folder below it.
    var visibleItems: [FileItem] {
        guard let browser, let currentPath else { return [] }
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let entries = (try? browser.children(of: currentPath, search: query, recursive: !query.isEmpty, sort: sort, direction: direction)) ?? []
        var hue = 0
        return entries.filter { !wasMoved($0.path) }.map { entry in
            var item = FileItem(entry: entry)
            if !item.sizeHidden { item.hue = hue % 5; hue += 1 }
            return item
        }
    }

    var selected: FileItem? {
        guard let selectedItem, !wasMoved(selectedItem) else { return nil }
        if let entry = browser?.entry(at: selectedItem) { return FileItem(entry: entry) }
        return (items + oldItems).first { $0.id == selectedItem }
    }

    /// Checking requires a coherent saved scan and, in the normal app, a scan
    /// completed in this session for the chosen folder.
    var canCheckForTrash: Bool {
        guard trashFlow != nil, let browser, !stale, !scanning, !trashBusy, browseStage == .list else { return false }
        if isFixture { return true }
        return explicitScanID != nil && explicitScanID == browser.snapshot.id && chosenRoot == browser.snapshot.root
    }
    func isCheckable(_ item: FileItem) -> Bool { canCheckForTrash && item.coverage == .complete && item.bytes != nil && item.path != browser?.rootPath }

    var checkDisabledNote: String? {
        if canCheckForTrash { return nil }
        if stale { return "Scan again before checking more items for Trash. Sizes still describe the earlier scan." }
        if scanning { return "Checking for Trash is off while a scan runs." }
        if !isFixture && browser != nil && explicitScanID == nil { return "Scan this folder again in this session before checking items for Trash." }
        return nil
    }

    var checkedTotal: Int64 { checkedPaths.reduce(0) { $0 + (browser?.entry(at: $1)?.knownApparentBytes ?? 0) } }
    func isChecked(_ path: String) -> Bool { checkedPaths.contains(path) }

    private func wasMoved(_ path: String) -> Bool { movedPaths.contains { path == $0 || path.hasPrefix($0 + "/") } }

    // MARK: Navigation (never changes checks)

    /// Every navigation path is inert while the Trash review or outcome holds the list
    /// column, so Cancel returns to the exact folder, position and selection by construction.
    var listNavigable: Bool { browseStage == .list }

    /// True when the folder changed together with the page (a jump from Overview): the
    /// page fade then carries the change and the rows, crumbs and inspector swap directly,
    /// so their fade does not compound with the page's.
    @Published private(set) var folderArrivesWithPage = false

    func navigate(_ path: String) {
        guard listNavigable, let browser, (try? browser.breadcrumbs(to: path)) != nil, !wasMoved(path) else { return }
        folderArrivesWithPage = false
        let previous = currentPath
        navigationStep = previous.map { Self.depth(path) > Self.depth($0) ? 1 : Self.depth(path) < Self.depth($0) ? -1 : 0 } ?? 0
        currentPath = path
        search = ""
        // Returning to an ancestor: bring the row we came through back into view and inspect it.
        if let previous, previous.hasPrefix(path == "/" ? "/" : path + "/") {
            let remainder = previous.dropFirst(path == "/" ? 1 : path.count + 1)
            let row = (path == "/" ? "/" : path + "/") + (remainder.split(separator: "/").first.map(String.init) ?? "")
            scrollTarget = row
            selectedItem = row
        } else {
            scrollTarget = nil
        }
        navigationCount += 1
    }

    private static func depth(_ path: String) -> Int { path.split(separator: "/").count }

    /// Click anywhere on a row: inspect it; a folder also opens.
    func open(_ item: FileItem) {
        guard listNavigable else { return }
        selectedItem = item.path
        if item.directory, browser?.entry(at: item.path)?.isDirectory == true {
            navigate(item.path)
            selectedItem = item.path
        }
    }

    func back() { guard listNavigable else { return }; if let currentPath, let parent = browser?.parent(of: currentPath) { navigate(parent) } }

    /// From Overview: open Browse at the item's folder with the item inspected.
    func reveal(inBrowse path: String) {
        show(.browse)
        // During a review the user lands on the open review; nothing moves under it.
        guard listNavigable, let browser, let entry = browser.entry(at: path) else { return }
        if let parent = browser.parent(of: entry.path) ?? Optional(browser.rootPath) { navigate(parent) }
        // The page fade is the only spatial cue for a jump from another page.
        navigationStep = 0
        folderArrivesWithPage = true
        selectedItem = path
        scrollTarget = path
        revealedPath = path
        revealCount += 1
        navigationCount += 1
    }

    /// Leaving Settings by a tab: the tab highlight then fades in at its destination
    /// instead of sliding across the bar while it fades.
    @Published private(set) var pageChangeLeftSettings = false
    func show(_ page: Screen) {
        pageChangeLeftSettings = settingsOpen
        settingsOpen = false
        screen = page
    }
    func openSettingsPage() { settingsOpen = true }
    func closeSettingsPage() { settingsOpen = false }
    func toggleSettingsPage() { settingsOpen.toggle() }

    func consumeReveal() { revealedPath = nil }

    func selectJob(_ job: PresentedJob) { selectedJob = job.id; show(.cleanups) }

    // MARK: Checks (never navigate)

    func toggleChecked(_ path: String) {
        guard let entry = browser?.entry(at: path), isCheckable(FileItem(entry: entry)) else { return }
        if checkedPaths.contains(path) { checkedPaths.remove(path) } else { checkedPaths.insert(path) }
    }
    func clearChecks() { guard browseStage == .list else { return }; checkedPaths = [] }

    // MARK: Trash review and outcome

    func requestTrashReview() {
        guard canCheckForTrash, !checkedPaths.isEmpty, let trashFlow, let snapshot = browser?.snapshot else { return }
        let paths = checkedPaths.sorted()
        trashBusy = true; error = nil
        Task {
            defer { trashBusy = false }
            await preferencesTask?.value
            do {
                review = try await trashFlow.review(snapshot: snapshot, paths: paths)
                outcome = nil
                browseStage = .review
            } catch {
                if let failure = error as? ManualTrashError {
                    switch failure {
                    case .requiresRescan, .changed, .incomplete, .referenceUnavailable, .identityUnavailable: stale = true; explicitScanID = nil
                    default: break
                    }
                }
                self.error = "Couldn’t review the selection: \(error.localizedDescription)"
            }
        }
    }

    var canConfirmTrash: Bool { review != nil && !trashBusy && !stale && confirmHeldReason == nil }

    func confirmTrash() {
        guard canConfirmTrash, let trashFlow, let review else { return }
        if !isFixture { guard explicitScanID == review.snapshotID, chosenRoot == review.root else { return } }
        trashBusy = true
        Task {
            defer { trashBusy = false }
            do {
                let result = try await trashFlow.execute(reviewID: review.id)
                record(result)
            } catch {
                self.review = nil
                browseStage = .list
                // No batch outcome: require fresh evidence before another action.
                stale = true; explicitScanID = nil
                self.error = "Couldn’t complete this Trash request: \(error.localizedDescription). Scan again before another file action."
            }
        }
    }

    private func record(_ result: TrashOutcomeModel) {
        outcome = result
        review = nil
        browseStage = .outcome
        for item in result.items where item.status == .moved {
            movedPaths.insert(item.path)
            checkedPaths.remove(item.path)
        }
        oldItems.removeAll { wasMoved($0.path) }
        if let currentPath, wasMoved(currentPath), let rootPath = browser?.rootPath { navigate(rootPath) }
        if let selectedItem, wasMoved(selectedItem) { self.selectedItem = nil }
        // Core decides whether a rescan is required; only the shown scan is marked stale here.
        if result.requiresRescan || result.persistenceError != nil || result.items.contains(where: { $0.status == .moved || $0.status == .unknown }) {
            stale = true
            explicitScanID = nil
        }
    }

    func cancelReview() {
        guard !trashBusy, browseStage == .review else { return }
        let id = review?.id
        review = nil
        browseStage = .list
        if let id, let trashFlow { Task { await trashFlow.discard(reviewID: id) } }
    }

    func closeOutcome() { guard browseStage == .outcome else { return }; browseStage = .list }

    // MARK: Scanning

    func beginChosenScan(_ url: URL) {
        guard scanControlsDisabledReason == nil, !scanning else { return }
        chosenRoot = url.standardizedFileURL.path
        startScan(url)
    }

    func rescan() {
        guard scanControlsDisabledReason == nil, !scanning, let root else { return }
        chosenRoot = root.standardizedFileURL.path
        startScan(root)
    }

    private func startScan(_ url: URL) {
        guard !isFixture, let inventory else { return }
        scanning = true; scanRoot = url; cancelRequested = false; viewingSavedDuringScan = false
        error = nil; notice = nil
        let retention = preferences.retention
        scanTask = Task {
            await preferencesTask?.value
            do {
                let result = try await inventory.scan(root: url, retention: retention)
                // Core returned a committed snapshot. Present it even if Cancel arrived late.
                if cancelRequested { notice = "Cancel arrived after the scan was saved, so the saved result is shown." }
                saved.append(result)
                // This scan was started here for the chosen folder. Core returns its
                // canonical root (for example /private/var for /var), which is authoritative.
                chosenRoot = result.root
                explicitScanID = result.id
                checkedPaths = []; movedPaths = []; outcome = nil
                show(result)
            } catch is CancellationError {
                notice = "Scan cancelled. Nothing was changed, and the previous saved scan is unchanged."
            } catch {
                self.error = "Couldn’t read this folder: \(error.localizedDescription)"
            }
            scanning = false; scanRoot = nil; scanTask = nil; viewingSavedDuringScan = false
        }
    }

    func cancelScan() {
        guard scanning else { return }
        if isFixture {
            scanning = false; scanRoot = nil; viewingSavedDuringScan = false
            notice = "Example scan cancelled. Nothing was read or changed."
            return
        }
        cancelRequested = true
        scanTask?.cancel()
    }

    // MARK: Preferences

    func setPreference<Value>(_ keyPath: WritableKeyPath<UserPreferences, Value>, to newValue: Value) {
        guard settingsLoaded else { return }
        let oldRetention = preferences.retention
        preferences[keyPath: keyPath] = newValue
        let value = preferences
        let previous = preferencesTask
        let store = preferencesStore, inventory = inventory
        preferencesTask = Task {
            await previous?.value
            do {
                try await store.save(value)
                if oldRetention != value.retention, let inventory { try await inventory.applyRetention(value.retention) }
            } catch { self.error = "Couldn’t save settings: \(error.localizedDescription)" }
        }
    }

    var retentionLocked: Bool { scanning || trashBusy || browseStage != .list }

    private func loadSettingsAndSaved() async {
        do {
            preferences = try await preferencesStore.load(defaults: Self.firstLaunchPreferences)
            if preferences.rememberLastScan { await loadSaved() }
        } catch { self.error = "Couldn’t load settings: \(error.localizedDescription)" }
        settingsLoaded = true
    }

    func refreshJobs() async {
        guard !isFixture, let jobStore else { return }
        do {
            var records = try await jobStore.jobs()
            for index in records.indices where records[index].status == .queued { records[index] = try await jobStore.get(id: records[index].id) }
            jobs = records.sorted { $0.createdAt > $1.createdAt }.map(Self.present)
        } catch { self.error = "Couldn’t load cleanup requests: \(error.localizedDescription)" }
    }

    private static func present(_ job: CleanupJob) -> PresentedJob {
        PresentedJob(id: job.id.uuidString, date: job.createdAt, requester: job.requester, status: job.status.rawValue, goal: job.targetBytes, before: job.beforeBytes, after: job.afterBytes, message: job.message)
    }

    private func loadSaved() async {
        guard let inventory, let jobStore else { return }
        do {
            saved = try await inventory.snapshots()
            if let snapshot = saved.max(by: { $0.createdAt < $1.createdAt }) { show(snapshot) }
            jobs = try await jobStore.jobs().sorted { $0.createdAt > $1.createdAt }.map(Self.present)
        } catch { self.error = "Couldn’t load saved scans: \(error.localizedDescription)" }
    }

    private func show(_ snapshot: InventorySnapshot) {
        do { browser = try InventoryBrowser(snapshot: snapshot) }
        catch { self.error = error.localizedDescription; browser = nil; return }
        currentPath = snapshot.root; stale = snapshot.isStale; scrollTarget = nil; navigationCount += 1
        let previous = saved.filter { $0.root == snapshot.root && $0.createdAt < snapshot.createdAt }.max { $0.createdAt < $1.createdAt }
        let growth = Dictionary((previous.map { compareSnapshots($0, snapshot) } ?? []).map { ($0.path, $0.changeBytes) }, uniquingKeysWith: { first, _ in first })
        root = URL(fileURLWithPath: snapshot.root); scanDate = snapshot.createdAt; comparisonDate = previous?.createdAt
        total = snapshot.capacity?.totalBytes; available = snapshot.capacity?.availableBytes; coverageErrors = snapshot.errors
        let direct = (try? browser?.children(of: snapshot.root)) ?? []
        items = direct.enumerated().map { index, entry in FileItem(entry: entry, hue: index % 5, growth: growth[entry.path]) }
        oldItems = snapshot.entries.filter { !$0.isDirectory && $0.modifiedAt != nil && $0.coverage == .complete }
            .sorted { $0.apparentBytes > $1.apparentBytes }.prefix(20).map { FileItem(entry: $0, growth: growth[$0.path]) }
        if selectedItem.flatMap({ browser?.entry(at: $0) }) == nil { selectedItem = items.first { !$0.sizeHidden }?.id }
    }

    // MARK: Fixture

    private func loadFixture() {
        browser = try? InventoryBrowser(snapshot: FixtureData.snapshot)
        currentPath = FixtureData.root
        root = URL(fileURLWithPath: FixtureData.root)
        scanDate = FixtureData.scanDate; comparisonDate = FixtureData.comparisonDate
        total = FixtureData.snapshot.capacity?.totalBytes; available = FixtureData.snapshot.capacity?.availableBytes
        coverageErrors = ["Some folders could not be read, so the sizes they affect are unknown."]
        items = FixtureData.categories
        oldItems = [FixtureData.olderPreviews, FixtureData.installers].compactMap { path in
            FixtureData.snapshot.entries.first { $0.path == path }.map { FileItem(entry: $0) }
        }
        jobs = FixtureData.jobs
        selectedItem = FixtureData.root + "/Documents"; selectedJob = "1024"
    }

    /// Puts the fixture window into one named scene. Fixture mode only.
    func apply(_ scene: FixtureScene) {
        guard isFixture else { return }
        switch scene {
        case .overview: screen = .overview
        case .settings: screen = .overview; settingsOpen = true
        case .browse: screen = .browse
        case .browseTree:
            screen = .browse
            navigate(FixtureData.root + "/Downloads")
            checkedPaths = [FixtureData.olderPreviews, FixtureData.installers]
            selectedItem = FixtureData.installers
        case .empty:
            screen = .overview
            browser = nil; currentPath = nil; root = nil; scanDate = nil; comparisonDate = nil
            total = nil; available = nil; items = []; oldItems = []; coverageErrors = []; selectedItem = nil
        case .scanning:
            screen = .overview
            scanning = true; scanRoot = URL(fileURLWithPath: FixtureData.root)
        case .trashReview, .trashOutcome:
            screen = .browse
            navigate(FixtureData.root + "/Downloads")
            checkedPaths = [FixtureData.olderPreviews, FixtureData.installers]
            selectedItem = FixtureData.installers
            guard let flow = trashFlow as? FixtureTrashFlow, let snapshot = browser?.snapshot,
                  let prepared = try? flow.reviewNow(snapshot: snapshot, paths: checkedPaths.sorted()) else { return }
            review = prepared
            browseStage = .review
            if scene == .trashOutcome, let result = try? flow.executeNow(reviewID: prepared.id) { record(result) }
        case .cleanupResult:
            screen = .cleanups; selectedJob = "1024"
        }
    }
}
