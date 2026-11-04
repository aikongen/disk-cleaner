import SwiftUI
import AppKit
import DiskCleanerCore

@main
struct DiskCleanerApplication: App {
    @StateObject private var model = CleanerModel()
    var body: some Scene {
        WindowGroup("Disk Cleaner") {
            CleanerWindow(model: model)
                .preferredColorScheme(.dark)
                .tint(.gray)
                .frame(minWidth: 960, minHeight: 720)
        }
        .defaultSize(width: 1200, height: 840)
        .windowStyle(.hiddenTitleBar)
        .commands {
            // ⌘, opens the Settings page in the main window; there is no Settings window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSettingsPage() }.keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}

struct CleanerWindow: View {
    @ObservedObject var model: CleanerModel
    @StateObject private var presentation = CleanerPresentation()
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Page visibility; a preview frame may pin it mid fade-through.
    private func visibility(_ screen: Screen) -> Double? {
        if let settings = motionFrame?.settings { return screen == model.screen ? (model.settingsOpen ? 1 - settings.out : settings.in) : 0 }
        guard let tab = motionFrame?.tab else { return nil }
        return screen == tab.to ? tab.in : screen == tab.from ? 1 - tab.out : 0
    }
    /// Notices slide from under the top bar; under Reduce Motion they only fade.
    private var bannerTransition: AnyTransition { reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity) }
    private var settingsVisibility: Double? {
        motionFrame?.settings.map { model.settingsOpen ? $0.in : 1 - $0.out }
    }
    /// A tab page is shown unless the Settings page covers it; it stays mounted either way.
    private func shows(_ screen: Screen) -> Bool { !model.settingsOpen && model.screen == screen }
    var body: some View {
        VStack(spacing: 0) {
            CleanerNavigation(model: model).zIndex(2)
            // Notices slide down from under the top bar while the page moves with them on the
            // same spring, as one motion; dismissing reverses it.
            VStack(spacing: 0) {
                if let error = model.error {
                    ErrorNotice(message: error) { model.error = nil }.transition(bannerTransition)
                }
                if let notice = model.notice {
                    ErrorNotice(message: notice, tone: Paint.slate) { model.notice = nil }.transition(bannerTransition)
                }
            }
            .frame(maxWidth: .infinity).clipped().zIndex(1)
            // Each page stays mounted, keeping its scroll position and local state.
            // Pages fade through; measurements never interpolate.
            ZStack(alignment: .topLeading) {
                PersistentPage(active: shows(.overview), pinned: visibility(.overview)) { OverviewScreen(model: model, presentation: presentation) }
                PersistentPage(active: shows(.browse), pinned: visibility(.browse), scrollLocked: model.browseStage != .list) { BrowseScreen(model: model) }
                PersistentPage(active: shows(.cleanups), pinned: visibility(.cleanups)) { JobsScreen(model: model) }
                PersistentPage(active: model.settingsOpen, pinned: settingsVisibility) { SettingsPage(model: model) }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.isFixture {
                HStack { Text("Preview · example data · no disk actions"); Spacer() }
                    .font(.system(size: 11)).foregroundStyle(Paint.secondary)
                    .padding(.horizontal, 16).frame(height: 25)
                    .background(.black.opacity(0.12)).overlay(alignment: .top) { Rule() }
            }
        }
        .animation(CleanerMotion.layout(CleanerMotion.disclosure, reduceMotion: reduceMotion), value: model.error)
        .animation(CleanerMotion.layout(CleanerMotion.disclosure, reduceMotion: reduceMotion), value: model.notice)
        // Figures and labels change their text directly; only position and opacity move.
        .contentTransition(.identity)
        .background { WindowAtmosphere() }
        .foregroundStyle(Color(white: 0.94)).font(.system(size: 13))
        .task {
            guard !model.isFixture else { return }
            while !Task.isCancelled {
                await model.refreshJobs()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}

@MainActor
final class CleanerPresentation: ObservableObject {
    @Published var scopeOpen = false
}

struct PersistentPage<Content: View>: View {
    let active: Bool
    var pinned: Double? = nil
    /// Held while the Trash review covers the list, so the list's offset cannot change.
    var scrollLocked = false
    @ViewBuilder var content: Content
    @Environment(\.motionFrame) private var motionFrame
    @State private var viewport: CGFloat = 0
    var body: some View {
        // The reader encloses the page's ScrollView, so the proxy given to the content
        // controls this scroll view (back-restore and scrolling a disclosure into view).
        ScrollViewReader { proxy in
            ScrollView {
                content.padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .transaction { $0.animation = nil }
                    .environment(\.pageScroller, proxy)
                    .environment(\.pageViewportHeight, viewport)
            }
            .defaultScrollAnchor(motionFrame?.scrolledToBottom == true ? .bottom : .top)
            .scrollDisabled(scrollLocked)
            .coordinateSpace(.named("page"))
        }
        .background { GeometryReader { geometry in Color.clear.onAppear { viewport = geometry.size.height }.onChange(of: geometry.size.height) { _, height in viewport = height } } }
        .scrollIndicators(.automatic)
        .opacity(pinned ?? (active ? 1 : 0)).allowsHitTesting(active).disabled(!active).accessibilityHidden(!active)
        .zIndex(active ? 1 : 0)
        // Fade-through: the leaving page is gone in 0.07 s, the arriving one starts 0.05 s in.
        .animation(active ? CleanerMotion.fadeIn : CleanerMotion.fadeOut, value: active)
    }
}

struct CleanerNavigation: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.motionFrame) private var motionFrame
    private static func width(_ screen: Screen) -> CGFloat { screen == .browse ? 112 : 96 }
    private static func leading(_ screen: Screen) -> CGFloat {
        Screen.allCases.prefix { $0 != screen }.reduce(0) { $0 + width($1) + 2 }
    }
    private func labelOpacity(_ screen: Screen) -> Double {
        if let tab = motionFrame?.tab {
            return screen == tab.to ? 0.76 + 0.20 * tab.pill : screen == tab.from ? 0.96 - 0.20 * tab.pill : 0.76
        }
        if motionFrame?.settings != nil { return model.screen == screen ? 0.76 + 0.20 * pillOpacity : 0.76 }
        return model.screen == screen && !model.settingsOpen ? 0.96 : 0.76
    }
    /// The tab highlight steps aside while Settings is shown; Back brings it back.
    private var pillOpacity: Double {
        if let settings = motionFrame?.settings { return model.settingsOpen ? 1 - settings.out : settings.in }
        return model.settingsOpen ? 0 : 1
    }
    private var pill: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(.white.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.16)))
    }
    var body: some View {
        ZStack {
            HStack(spacing: 2) {
                ForEach(Screen.allCases, id: \.self) { screen in
                    Button { model.show(screen) } label: {
                        // One weight for all labels (no glyph-width snap). Brightness moves with
                        // the highlight: on its spring between tabs, on its fade for Settings.
                        Text(screen.title).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.white.opacity(labelOpacity(screen)))
                            .animation(model.settingsOpen ? CleanerMotion.fadeOut : CleanerMotion.fadeIn, value: model.settingsOpen)
                            .animation(model.pageChangeLeftSettings ? CleanerMotion.fadeIn : CleanerMotion.selection, value: model.screen)
                            .frame(width: Self.width(screen), height: 30)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            // One highlight, placed by the current page: it slides between tabs on the
            // selection spring; it fades out for Settings and fades back in where it lands.
            .background(alignment: .leading) {
                if let tab = motionFrame?.tab {
                    let x = Self.leading(tab.from) + (Self.leading(tab.to) - Self.leading(tab.from)) * tab.pill
                    let w = Self.width(tab.from) + (Self.width(tab.to) - Self.width(tab.from)) * tab.pill
                    pill.frame(width: w, height: 30).offset(x: x)
                } else {
                    pill.frame(width: Self.width(model.screen), height: 30).offset(x: Self.leading(model.screen))
                        .animation(model.pageChangeLeftSettings ? nil : CleanerMotion.selection, value: model.screen)
                        .opacity(pillOpacity)
                        .animation(model.settingsOpen ? CleanerMotion.fadeOut : CleanerMotion.fadeIn, value: model.settingsOpen)
                }
            }
            .padding(3).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.08)))
            HStack(spacing: 10) {
                Spacer()
                if model.isFixture { ExamplePill() }
                Button { model.toggleSettingsPage() } label: { Image(systemName: "gearshape") }
                    .buttonStyle(IconStyle(size: 28, active: model.settingsOpen)).help(model.settingsOpen ? "Back (Esc)" : "Settings (⌘,)")
                    .accessibilityLabel("Settings")
            }.padding(.trailing, 16)
        }
        .frame(height: 52).frame(maxWidth: .infinity)
        .background(.ultraThinMaterial).overlay(alignment: .bottom) { Rule() }
    }
}

/// Folder, freshness and rescan controls for a completed scan.
struct ScanControls: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text((model.stale ? "Saved scan · out of date" : "Saved scan") + (model.scanDate.map { " · \(dateText($0, time: true))" } ?? ""))
                    .foregroundStyle(model.stale ? Paint.warning : Paint.secondary)
                Spacer(minLength: 8)
                Button("Choose Folder…") { FolderChooser.choose { model.beginChosenScan($0) } }
                    .buttonStyle(NeutralStyle(compact: true))
                Button("Scan Again") { model.rescan() }.buttonStyle(NeutralStyle(compact: true))
            }
            .disabled(model.scanControlsDisabledReason != nil || model.scanning)
            .help(model.scanControlsDisabledReason ?? "")
            if let root = model.root, !model.isFixture {
                Text("Scope: \(root.path) only").font(.system(size: 11)).foregroundStyle(Paint.secondary).textSelection(.enabled)
            }
            if let reason = model.scanControlsStandingReason {
                Text(reason).font(.system(size: 11)).foregroundStyle(Paint.secondary)
            }
        }.font(.system(size: 12))
    }
}
