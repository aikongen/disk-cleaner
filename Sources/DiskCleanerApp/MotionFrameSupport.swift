import SwiftUI
import DiskCleanerCore

// Official preview frames for the motion critique. RenderPreview is static, so each
// frame pins one transition at an instant computed from the app's own curves
// (SwiftUI Spring and UnitCurve with the CleanerMotion values). They show what
// the declared motion interpolates, not a capture of the running app.
enum MotionClock {
    static let instants = [30, 70, 120, 180, 300] // milliseconds after the click
    static func spring(_ response: Double, _ ms: Int) -> Double {
        Spring(response: response, dampingRatio: 1).value(target: 1.0, time: Double(ms) / 1000)
    }
    static func ease(_ duration: Double, _ ms: Int, delay: Double = 0) -> Double {
        let t = Double(ms) / 1000 - delay
        return t <= 0 ? 0 : UnitCurve.easeOut.value(at: min(1, t / duration))
    }
    /// The fade-through rule: out 0.07 s; in 0.18 s starting at 0.05 s.
    static func out(_ ms: Int) -> Double { ease(CleanerMotion.fadeOutDuration, ms) }
    static func `in`(_ ms: Int) -> Double { ease(CleanerMotion.fadeInDuration, ms, delay: CleanerMotion.fadeInDelay) }
    static func swap(_ outgoing: CleanerModel, step: Int, _ ms: Int) -> MotionFrameOverride.Swap {
        .init(outgoing: outgoing, step: step, out: out(ms), in: `in`(ms), height: spring(0.28, ms))
    }
}

@MainActor
enum MotionFixtures {
    static func home() -> CleanerModel { CleanerModel(isFixture: true, scene: .browse) }
    static func downloads() -> CleanerModel {
        let model = home()
        if let folder = model.visibleItems.first(where: { $0.path == FixtureData.root + "/Downloads" }) { model.open(folder) }
        return model
    }
    static func backAtHome() -> CleanerModel { let model = downloads(); model.back(); return model }
}

struct MotionFramePreview: View {
    let title: String
    let ms: Int
    let model: CleanerModel
    let frame: MotionFrameOverride
    var height: CGFloat = 840
    var body: some View {
        CleanerWindow(model: model)
            .environment(\.motionFrame, frame)
            .overlay(alignment: .bottomTrailing) {
                Text("\(title) · \(ms) ms · computed frame")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5))
                    .padding(.trailing, 10).padding(.bottom, 2)
            }
            .preferredColorScheme(.dark).tint(.gray).frame(width: 1200, height: height)
    }
}

extension MotionFramePreview {
    @MainActor static func tab(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        var frame = MotionFrameOverride()
        frame.tab = (.overview, .browse, MotionClock.spring(0.25, ms), MotionClock.out(ms), MotionClock.in(ms))
        return MotionFramePreview(title: "Overview → Browse files", ms: ms, model: MotionFixtures.home(), frame: frame)
    }
    @MainActor static func drill(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        var frame = MotionFrameOverride(); frame.folder = MotionClock.swap(MotionFixtures.home(), step: 1, ms)
        return MotionFramePreview(title: "Open Downloads", ms: ms, model: MotionFixtures.downloads(), frame: frame)
    }
    @MainActor static func back(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        var frame = MotionFrameOverride(); frame.folder = MotionClock.swap(MotionFixtures.downloads(), step: -1, ms)
        return MotionFramePreview(title: "Back to Home", ms: ms, model: MotionFixtures.backAtHome(), frame: frame)
    }
    /// Default 840 pt window: the page is scrolled so the opening text is in view, as the
    /// app scrolls it on the same spring.
    @MainActor static func disclosure(_ i: Int, opening: Bool) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        let s = MotionClock.spring(0.28, ms)
        var frame = MotionFrameOverride(); frame.disclosureOpen = opening ? s : 1 - s; frame.scrolledToBottom = true
        return MotionFramePreview(title: opening ? "Open Scope and estimate" : "Close Scope and estimate", ms: ms, model: CleanerModel(isFixture: true, scene: .overview), frame: frame)
    }
    @MainActor static func review(_ i: Int, entering: Bool) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        let list = CleanerModel(isFixture: true, scene: .browseTree)
        let review = CleanerModel(isFixture: true, scene: .trashReview)
        var frame = MotionFrameOverride()
        frame.stage = MotionClock.swap(entering ? list : review, step: 0, ms)
        return MotionFramePreview(title: entering ? "Review for Trash" : "Cancel review", ms: ms, model: entering ? review : list, frame: frame)
    }
    @MainActor static func bannerExit(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        var frame = MotionFrameOverride()
        frame.bannerExit = (1 - MotionClock.ease(0.10, ms), 1 - MotionClock.spring(0.28, ms), CleanerModel(isFixture: true, scene: .scanning))
        return MotionFramePreview(title: "Scan finished · banner leaves", ms: ms, model: CleanerModel(isFixture: true, scene: .overview), frame: frame)
    }
    @MainActor static func request(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        let before = CleanerModel(isFixture: true, scene: .cleanupResult)
        let after = CleanerModel(isFixture: true, scene: .cleanupResult); after.selectedJob = "0842"
        var frame = MotionFrameOverride(); frame.request = MotionClock.swap(before, step: 0, ms); frame.pill = MotionClock.spring(0.25, ms)
        return MotionFramePreview(title: "Switch request 10:24 → 08:42", ms: ms, model: after, frame: frame)
    }
    /// In Downloads, inspecting Xcode_27.xip (a file) after the folder itself: the inspector
    /// changes at once; only the row highlight moves (selection spring 0.25 s).
    @MainActor static func rowSelect(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        let model = MotionFixtures.downloads()
        let from = model.selectedItem ?? ""
        if let file = model.visibleItems.first(where: { !$0.directory }) { model.open(file) }
        var frame = MotionFrameOverride(); frame.selection = (from, MotionClock.spring(0.25, ms))
        return MotionFramePreview(title: "Inspect a file in Downloads", ms: ms, model: model, frame: frame)
    }
    /// Settings was opened from Overview; the owner leaves it by clicking Browse files.
    /// The Settings page fades out, Browse fades in, and the tab highlight fades in at
    /// Browse files without sliding.
    @MainActor static func settingsExitViaTab(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        var frame = MotionFrameOverride(); frame.settings = (MotionClock.out(ms), MotionClock.in(ms))
        return MotionFramePreview(title: "Leave Settings by Browse files", ms: ms, model: MotionFixtures.home(), frame: frame)
    }
    @MainActor static func settings(_ i: Int) -> MotionFramePreview {
        let ms = MotionClock.instants[i]
        var frame = MotionFrameOverride(); frame.settings = (MotionClock.out(ms), MotionClock.in(ms))
        return MotionFramePreview(title: "Open Settings", ms: ms, model: CleanerModel(isFixture: true, scene: .settings), frame: frame)
    }
}
