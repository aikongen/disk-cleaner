import SwiftUI
import AppKit
import DiskCleanerCore

extension Paint {
    static func hue(_ index: Int?) -> Color { index.map { palette[$0 % palette.count] } ?? slate }
    /// Destructive text per macOS convention: a red label on a neutral button, never a fill.
    static let destructive = Color(red: 0.96, green: 0.47, blue: 0.43)
    static let moved = teal
    static let warning = gold
}

enum CleanerMotion {
    static let selection = Animation.spring(response: 0.25, dampingFraction: 1, blendDuration: 0.08)
    static let disclosure = Animation.spring(response: 0.28, dampingFraction: 1, blendDuration: 0.08)
    /// Card heights and the content below a swap follow the arriving content on this spring.
    static let navigate = Animation.spring(response: 0.28, dampingFraction: 1, blendDuration: 0.08)
    /// Fade-through, the one rule for every swap: the old content is gone in 0.07 s and the
    /// new content starts 0.05 s after the click and takes 0.18 s, so old and new are never
    /// both half visible. Cards, header and inspector stay put; only their contents swap.
    static let fadeOut = Animation.easeOut(duration: 0.07)
    static let fadeIn = Animation.easeOut(duration: 0.18).delay(0.05)
    static let fadeInDelay = 0.05
    static let fadeInDuration = 0.18
    static let fadeOutDuration = 0.07
    /// Scanning banner leaving at the end of a scan.
    static let bannerOut = Animation.easeOut(duration: 0.10)
    /// Release of press feedback; pressing itself stays instant.
    static let release = Animation.easeOut(duration: 0.12)
    /// Teal and Violet ground crossfade after a Settings change.
    static let appearance = Animation.easeOut(duration: 0.24)
    /// Rows arriving after a folder change travel 10 pt; leaving rows drift 6 pt the same way.
    static let arriveTravel: CGFloat = 10
    static let leaveTravel: CGFloat = 6
    /// Under Reduce Motion, springs that move layout become a short ease-out; fades stay.
    static func layout(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeOut(duration: 0.16) : animation
    }
}

extension AnyTransition {
    /// Fade-through with direction: deeper = rows arrive from the trailing side and the
    /// leaving rows drift toward the leading side; back is the mirror; 0 is a plain fade.
    static func navigation(step: Int, reduceMotion: Bool) -> AnyTransition {
        let side = reduceMotion ? 0 : CGFloat(step.signum())
        return .asymmetric(
            insertion: AnyTransition.offset(x: side * CleanerMotion.arriveTravel).combined(with: .opacity).animation(CleanerMotion.fadeIn),
            removal: AnyTransition.offset(x: -side * CleanerMotion.leaveTravel).combined(with: .opacity).animation(CleanerMotion.fadeOut))
    }
    /// Fade-through in place, for content swaps without direction.
    static var fadeThrough: AnyTransition { navigation(step: 0, reduceMotion: true) }
}

/// Official preview frames only. Pins one transition at a computed instant so the
/// static RenderPreview tool can show it; nil everywhere in the running app.
struct MotionFrameOverride {
    /// `out` and `in` are the fade-through progress of the leaving and arriving content
    /// (0 to 1); `height` is the layout spring's progress.
    struct Swap { let outgoing: CleanerModel; let step: Int; let out: Double; let `in`: Double; let height: Double }
    var tab: (from: Screen, to: Screen, pill: Double, out: Double, in: Double)?
    var disclosureOpen: Double?
    var folder: Swap?
    /// Review step: `outgoing` is the list-stage model when entering, the review-stage model when cancelling.
    var stage: Swap?
    var request: Swap?
    /// Settings page opening (model.settingsOpen true) or closing.
    var settings: (out: Double, in: Double)?
    var pill: Double?
    /// Row selection within a folder: the previously inspected row and the highlight's progress.
    var selection: (from: String, progress: Double)?
    /// Scanning banner leaving: banner opacity and how much of its slot is still open.
    var bannerExit: (opacity: Double, open: Double, source: CleanerModel)?
    /// Start scrolled to the bottom (disclosure frames, whose card sits below the fold).
    var scrolledToBottom = false
}
private struct MotionFrameKey: EnvironmentKey { static var defaultValue: MotionFrameOverride? { nil } }
private struct PageScrollerKey: EnvironmentKey { static var defaultValue: ScrollViewProxy? { nil } }
private struct PageViewportKey: EnvironmentKey { static var defaultValue: CGFloat { 0 } }
extension EnvironmentValues {
    var motionFrame: MotionFrameOverride? { get { self[MotionFrameKey.self] } set { self[MotionFrameKey.self] = newValue } }
    /// The scroll proxy of the page's own ScrollView (the reader encloses it).
    var pageScroller: ScrollViewProxy? { get { self[PageScrollerKey.self] } set { self[PageScrollerKey.self] = newValue } }
    /// Visible height of the page's ScrollView.
    var pageViewportHeight: CGFloat { get { self[PageViewportKey.self] } set { self[PageViewportKey.self] = newValue } }
}

extension ScrollViewProxy {
    /// Scrolls in the same update, without animation, so the restored row is in place
    /// before the arriving content fades in.
    func jump<ID: Hashable>(to id: ID, anchor: UnitPoint?) {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { scrollTo(id, anchor: anchor) }
    }
}

/// Marks which state a swapped view belongs to.
struct MotionStateKey: LayoutValueKey { static let defaultValue = "" }

/// Container for a swap: it takes the arriving view's size at once (and the surrounding
/// card and content follow on the layout spring), so nothing snaps when the leaving view
/// is removed. The leaving view keeps its old key and fades on top-leading.
/// `pinned` exists only for preview frames: it blends the leaving and arriving heights.
struct ArrivingSized: Layout {
    let current: String
    var pinned: Double? = nil
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let free = ProposedViewSize(width: proposal.width, height: nil)
        let arriving = subviews.last { $0[MotionStateKey.self] == current } ?? subviews.last
        guard let arriving else { return .zero }
        var size = arriving.sizeThatFits(free)
        if let pinned, let leaving = subviews.first(where: { $0[MotionStateKey.self] != current }) {
            let old = leaving.sizeThatFits(free).height
            size.height = old + (size.height - old) * pinned
        }
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        }
    }
}

/// One value that fades through when `key` changes while everything around it (card,
/// title, rule) stays drawn. A preview frame passes the outgoing value and the progress.
struct FadeSwap<Content: View>: View {
    let key: String
    var alignment: Alignment = .topLeading
    var outgoing: Content? = nil
    var fade: (out: Double, in: Double)? = nil
    @ViewBuilder var content: Content
    var body: some View {
        ZStack(alignment: alignment) {
            if let fade, let outgoing {
                outgoing.opacity(1 - fade.out)
                content.opacity(fade.in)
            } else {
                content.transaction { $0.animation = nil }.id(key).transition(.fadeThrough)
            }
        }
        .animation(CleanerMotion.fadeIn, value: key)
    }
}

/// Reports a fraction of its child's height, top-aligned; used only by preview frames
/// to stand in for the disclosure viewport mid-animation.
struct FractionalHeight: Layout {
    var fraction: Double
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: size.height * max(0, min(1, fraction)))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

private struct VioletAppearanceKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var violetAppearance: Bool { get { self[VioletAppearanceKey.self] } set { self[VioletAppearanceKey.self] = newValue } }
}

struct WindowAtmosphere: View {
    @Environment(\.violetAppearance) private var violet
    var body: some View {
        // The teal ground is always drawn and opaque; the violet ground fades over it. Either
        // direction is one layer's opacity, so the window never dips toward black mid-change.
        ZStack {
            ZStack {
                LinearGradient(colors: [DiskCleanerAppearance.greenTop, Paint.background], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [DiskCleanerAppearance.greenGlow1.opacity(0.48), .clear], center: .topLeading, startRadius: 0, endRadius: 850)
                RadialGradient(colors: [DiskCleanerAppearance.greenGlow2.opacity(0.38), .clear], center: .trailing, startRadius: 0, endRadius: 750)
            }
            GeometryReader { geometry in
                let radius = max(geometry.size.width, geometry.size.height)
                ZStack {
                    DiskCleanerAppearance.violetGround
                    RadialGradient(colors: [DiskCleanerAppearance.violetGlow1.opacity(0.26), .clear], center: UnitPoint(x: 0.56, y: 0.48), startRadius: 0, endRadius: radius * 0.48)
                    RadialGradient(colors: [DiskCleanerAppearance.violetGlow2.opacity(0.30), .clear], center: UnitPoint(x: 0.72, y: 0.80), startRadius: 0, endRadius: radius * 0.50)
                }
            }
            .opacity(violet ? 1 : 0)
        }
        .animation(CleanerMotion.appearance, value: violet)
        .ignoresSafeArea()
    }
}

struct PanelSurface: View {
    @Environment(\.violetAppearance) private var violet
    var raised = false
    var radius: CGFloat = 11
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(.regularMaterial)
            .overlay { RoundedRectangle(cornerRadius: radius, style: .continuous).fill(.black.opacity(violet ? (raised ? 0.30 : 0.24) : 0)).animation(CleanerMotion.appearance, value: violet) }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(raised ? 0.16 : 0.08), .white.opacity(raised ? 0.07 : 0.04)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(raised ? 0.28 : 0.17), .white.opacity(0.07)], startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: .black.opacity(raised ? 0.20 : 0), radius: 20, y: 10)
    }
}

/// Neutral outlined button. Used for the disabled cleanup CTA and primary steps.
struct GhostStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var tint: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(tint.opacity(enabled ? 0.94 : 0.50))
            .padding(.horizontal, 16).frame(height: 36)
            .background(.white.opacity(configuration.isPressed && enabled ? 0.11 : 0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(configuration.isPressed ? nil : CleanerMotion.release, value: configuration.isPressed)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(enabled ? 0.30 : 0.18)))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct NeutralStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: compact ? 12 : 13, weight: .medium))
            .foregroundStyle(.white.opacity(enabled ? 0.92 : 0.42))
            .padding(.horizontal, compact ? 10 : 13).frame(minHeight: compact ? 26 : 32)
            .background(.white.opacity(configuration.isPressed && enabled ? 0.15 : 0.065), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(configuration.isPressed ? nil : CleanerMotion.release, value: configuration.isPressed)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(enabled ? 0.14 : 0.08)))
            .contentShape(Rectangle())
    }
}

/// Square icon button (back chevron, gear, sort direction).
struct IconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var size: CGFloat = 30
    /// Shown as current, like the tab highlight (the gear while Settings is open).
    var active = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white.opacity(enabled ? (active ? 0.96 : 0.90) : 0.32))
            .frame(width: size, height: size)
            .background(.white.opacity(configuration.isPressed && enabled ? 0.15 : active ? 0.14 : 0.06), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .animation(active ? CleanerMotion.fadeIn : CleanerMotion.fadeOut, value: active)
            .animation(configuration.isPressed ? nil : CleanerMotion.release, value: configuration.isPressed)
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(.white.opacity(enabled ? 0.14 : 0.07)))
            .contentShape(Rectangle())
    }
}

/// Whole-row target: the full row is the hit area, with a pointing cursor.
struct WholeRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(.white.opacity(configuration.isPressed ? 0.07 : 0))
            .animation(configuration.isPressed ? nil : CleanerMotion.release, value: configuration.isPressed)
            .pointingCursor()
    }
}

extension View {
    func pointingCursor() -> some View { modifier(PointingCursor()) }
}

private struct PointingCursor: ViewModifier {
    @Environment(\.isEnabled) private var enabled
    func body(content: Content) -> some View {
        // set(), never push/pop: a row removed under the pointer by a drill-down cannot
        // leave the cursor stack unbalanced. A disabled control keeps the arrow.
        content.onContinuousHover { phase in
            if case .active = phase, enabled { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
    }
}

struct ExamplePill: View {
    var body: some View {
        Text("Example data – no scan has run")
            .font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.88))
            .padding(.horizontal, 8).frame(height: 20)
            .background(.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(0.14)))
            .fixedSize()
    }
}

struct ErrorNotice: View {
    let message: String
    var tone: Color = Paint.warning
    let dismiss: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(tone).frame(width: 7, height: 7)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Dismiss", action: dismiss).buttonStyle(NeutralStyle(compact: true))
        }
        .padding(.horizontal, 28).padding(.vertical, 8).background(.black.opacity(0.18))
        .overlay(alignment: .bottom) { Rule() }
    }
}

struct GroupCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }.frame(maxWidth: .infinity)
            .background { PanelSurface() }.clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}
struct Rule: View { var body: some View { Rectangle().fill(Paint.line).frame(height: 1) } }
struct Heading: View {
    let title: String
    var body: some View { Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(white: 0.82)).frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 2).padding(.bottom, 3) }
}
struct ValueRow: View {
    let title: String
    let value: String
    var marker: Color? = nil
    var body: some View {
        HStack(spacing: 10) {
            if let marker { RoundedRectangle(cornerRadius: 2).fill(marker).frame(width: 9, height: 9) }
            Text(title).foregroundStyle(Paint.secondary)
            Spacer(minLength: 12)
            Text(value).fontWeight(.medium).monospacedDigit().multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13)).padding(.horizontal, 16).frame(minHeight: 43)
    }
}
struct Hatch: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.24)))
            for offset in stride(from: -size.height, through: size.width, by: 5) {
                var path = Path(); path.move(to: CGPoint(x: offset, y: size.height)); path.addLine(to: CGPoint(x: offset + size.height, y: 0))
                context.stroke(path, with: .color(Color(white: 0.70)), lineWidth: 1.5)
            }
        }.clipped()
    }
}
struct RowChevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Paint.secondary).frame(width: 12) }
}
struct RelativeSizeBar: View {
    let fraction: Double
    let color: Color
    var body: some View {
        GeometryReader { proxy in
            RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.10))
                .overlay(alignment: .leading) { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: proxy.size.width * min(1, max(0, fraction))) }
        }.transaction { $0.animation = nil }
    }
}
struct FullPathText: View {
    let path: String
    var size: CGFloat = 11.5
    var body: some View {
        Text(path).font(.system(size: size, design: .monospaced)).foregroundStyle(Color(white: 0.78))
            .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
    }
}

/// Native checkbox, independent of the row's inspect/open target.
struct TrashCheckbox: View {
    let name: String
    let checked: Bool
    let enabled: Bool
    let toggle: () -> Void
    var body: some View {
        Toggle("Check \(name) for Trash", isOn: Binding(get: { checked }, set: { _ in toggle() }))
            .labelsHidden().toggleStyle(.checkbox).disabled(!enabled)
            .frame(width: 40, height: 38).contentShape(Rectangle())
            .opacity(enabled || checked ? 1 : 0.35)
    }
}

@MainActor
enum FolderChooser {
    static func choose(_ completion: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        panel.prompt = "Read Folder"; panel.message = "Choose the folder Disk Cleaner reads. Nothing is changed or removed."
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated { completion(url) }
        }
    }
}
