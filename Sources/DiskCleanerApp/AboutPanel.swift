import SwiftUI
import AppKit

/// The About panel: one reused, non-modal NSPanel (an owner-approved exception to the
/// in-window Settings rule). It holds no state; each open starts the lift again.
@MainActor
final class AboutPanelController {
    static let shared = AboutPanelController()
    private var panel: NSPanel?

    func show() {
        if let panel, panel.isVisible { panel.makeKeyAndOrderFront(nil); return }
        let panel = self.panel ?? makePanel()
        let host = NSHostingView(rootView: AboutContent().preferredColorScheme(.dark))
        host.sizingOptions = []
        panel.contentView = host
        if self.panel == nil { panel.center() }
        self.panel = panel
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 560),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.backgroundColor = NSColor(red: 11 / 255, green: 9 / 255, blue: 16 / 255, alpha: 1)
        panel.setFrame(NSRect(x: 0, y: 0, width: 480, height: 560), display: false)
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        return panel
    }
}

enum AboutLinks {
    static let releases = URL(string: "https://github.com/aikongen/disk-cleaner/releases")!
    static let source = URL(string: "https://github.com/aikongen/disk-cleaner")!
    static let problem = URL(string: "https://github.com/aikongen/disk-cleaner/issues/new")!
    static let licence = URL(string: "https://github.com/aikongen/disk-cleaner/blob/main/LICENSE")!
    static let maker = URL(string: "https://github.com/aikongen")!
}

struct AboutContent: View {
    private let info = Bundle.main.infoDictionary
    private var version: String? { info?["CFBundleShortVersionString"] as? String }
    private var build: String? { info?["CFBundleVersion"] as? String }
    private var versionText: String {
        guard let version else { return "Version not recorded" }
        return build.map { "Version \(version) (\($0))" } ?? "Version \(version)"
    }
    private let whatsNew: String?
    init() { whatsNew = AboutWhatsNew.bundled(version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) }

    var body: some View {
        ZStack(alignment: .top) {
            AboutGround()
            Circle().fill(RadialGradient(colors: [Color(red: 150 / 255, green: 110 / 255, blue: 1).opacity(0.45), .clear], center: .center, startRadius: 0, endRadius: 88))
                .frame(width: 260, height: 260).blur(radius: 10).offset(y: 50)
            VStack(spacing: 0) {
                AboutIcon().frame(width: 134, height: 134).padding(.top, 61)
                Text("Disk Cleaner").font(.system(size: 26, weight: .bold)).tracking(-0.26).padding(.top, 29)
                Text(versionText).font(.system(size: 13)).monospacedDigit().foregroundStyle(.white.opacity(0.55)).padding(.top, 6)
                Text("See what fills your Mac, choose exactly what goes, and give your AI agent an honest answer about free space.")
                    .font(.system(size: 14)).foregroundStyle(.white.opacity(0.78)).multilineTextAlignment(.center)
                    .lineSpacing(3).frame(width: 400).padding(.top, 8)
                if let whatsNew {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("What's new").fontWeight(.semibold).foregroundStyle(.white)
                        Text(whatsNew).foregroundStyle(.white.opacity(0.78)).lineLimit(2).multilineTextAlignment(.leading)
                    }
                    .font(.system(size: 12.5)).padding(.horizontal, 14).padding(.vertical, 5).frame(maxWidth: 420)
                    .background(RoundedRectangle(cornerRadius: 15, style: .continuous).fill(.white.opacity(0.07)))
                    .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                    .padding(.top, 12)
                }
                Spacer(minLength: 0)
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    AboutLinkRow(title: "Release notes", url: AboutLinks.releases)
                    AboutLinkRow(title: "Source on GitHub", url: AboutLinks.source, divider: true)
                    AboutLinkRow(title: "Report a problem", url: AboutLinks.problem, divider: true)
                    AboutLinkRow(title: "MIT licence", url: AboutLinks.licence, divider: true)
                }
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.12), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .padding(.horizontal, 40)
                AboutMark().padding(.top, 16).padding(.bottom, 10)
            }
        }
        .frame(width: 480, height: 560)
        .foregroundStyle(.white)
        .ignoresSafeArea()
    }
}

/// Window ground: the prototype's radial ellipse (80% x 60% at 50% 30%).
private struct AboutGround: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 11 / 255, green: 9 / 255, blue: 16 / 255)))
            context.translateBy(x: size.width * 0.5, y: size.height * 0.3)
            context.scaleBy(x: size.width * 0.8, y: size.height * 0.6)
            let stops: [Gradient.Stop] = [
                .init(color: Color(red: 0x2a / 255, green: 0x1a / 255, blue: 0x4d / 255), location: 0),
                .init(color: Color(red: 0x1b / 255, green: 0x12 / 255, blue: 0x33 / 255), location: 0.42),
                .init(color: Color(red: 0x10 / 255, green: 0x0c / 255, blue: 0x1c / 255), location: 0.74),
                .init(color: Color(red: 0x0b / 255, green: 9 / 255, blue: 0x10 / 255), location: 1)]
            context.fill(Path(CGRect(x: -2, y: -2, width: 4, height: 4)), with: .radialGradient(Gradient(stops: stops), center: .zero, startRadius: 0, endRadius: 1))
        }
    }
}

private struct AboutLinkRow: View {
    let title: String
    let url: URL
    var divider = false
    @State private var hovering = false
    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            HStack {
                Text(title).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Paint.blue)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.55)).padding(.trailing, 3)
            }
            .padding(.horizontal, 16).frame(minHeight: 30, maxHeight: 30)
            .background(.white.opacity(hovering ? 0.06 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .pointingCursor()
        .overlay(alignment: .top) { if divider { Rectangle().fill(.white.opacity(0.09)).frame(height: 1) } }
    }
}

private struct AboutMark: View {
    var body: some View {
        Button { NSWorkspace.shared.open(AboutLinks.maker) } label: {
            if let url = Bundle.main.url(forResource: "made-with-love-aikongen-dark", withExtension: "svg"), let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 28)
            } else {
                Text("Made with love by Aikongen").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7)).frame(height: 28)
            }
        }
        .buttonStyle(.plain).pointingCursor()
    }
}

/// The app icon drawn twice: the full icon with its baked-in yellow square covered by a
/// patch of ground, and a separate yellow square on top that lifts once on open.
///
/// Geometry is in the 1024 x 1024 space of assets/icon/icon-1024.png. The square was measured
/// once by scanning that PNG for yellow pixels (R > .6, G > .45, B < .5, R - B > .3, alpha > .5):
/// the face and its side span x 730...967, y 236...491; its cast shadow reaches about y 527.
/// The ground patch (722...1000 x 228...540) is filled with a bilinear blend of the ground colours
/// sampled at its four corners from the same PNG, and its edge is softened with a small blur.
struct AboutIcon: View {
    private static let unit: CGFloat = 1024
    private static let face = CGRect(x: 730, y: 236, width: 238, height: 238)
    private static let patch = CGRect(x: 722, y: 228, width: 278, height: 312)
    // Ground colours at the patch corners, measured from icon-1024.png (0...255 RGB).
    private static let topLeft = (58.0, 46.0, 79.0), topRight = (47.0, 38.0, 63.0)
    private static let bottomLeft = (44.0, 35.0, 60.0), bottomRight = (38.0, 32.0, 50.0)
    // The prototype lift: up 26 and right 14 of a 200-unit icon, turned 14 degrees.
    private static let liftX: CGFloat = 14 / 200 * 1024, liftY: CGFloat = -26 / 200 * 1024, liftTurn = 14.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lifted = false
    @State private var visible = true

    /// The 1024 px art the geometry was measured on, bundled as AboutIcon.png; the app icon is the fallback.
    private static let iconImage: NSImage = Bundle.main.url(forResource: "AboutIcon", withExtension: "png").flatMap { NSImage(contentsOf: $0) } ?? NSApp.applicationIconImage

    private func c(_ t: (Double, Double, Double)) -> Color { Color(red: t.0 / 255, green: t.1 / 255, blue: t.2 / 255) }

    var body: some View {
        GeometryReader { geometry in
            let k = geometry.size.width / Self.unit
            ZStack(alignment: .topLeading) {
                Image(nsImage: Self.iconImage).resizable().interpolation(.high).frame(width: geometry.size.width, height: geometry.size.height)
                    // The PNG is full bleed; its own rim radius is about 225 of 1024.
                    .clipShape(RoundedRectangle(cornerRadius: 225 * k, style: .continuous))
                ground.frame(width: Self.patch.width * k, height: Self.patch.height * k).blur(radius: 3 * k)
                    .offset(x: Self.patch.minX * k, y: Self.patch.minY * k)
                // The dashed ghost marks where the square sat.
                RoundedRectangle(cornerRadius: 56 * k, style: .continuous)
                    .strokeBorder(Color(red: 0xE0 / 255, green: 0xB3 / 255, blue: 0x40 / 255).opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                    .frame(width: Self.face.width * k, height: Self.face.height * k)
                    .offset(x: Self.face.minX * k, y: Self.face.minY * k).opacity(lifted ? 1 : 0)
                square(k).opacity(visible ? 1 : 0)
                    .rotationEffect(.degrees(lifted ? Self.liftTurn : 0))
                    .offset(x: Self.face.minX * k + (lifted ? Self.liftX * k : 0), y: Self.face.minY * k + (lifted ? Self.liftY * k : 0))
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
            .shadow(color: .black.opacity(0.55), radius: 15, y: 9)
            .shadow(color: Color(red: 140 / 255, green: 100 / 255, blue: 240 / 255).opacity(0.45), radius: 20)
        }
        .task {
            if reduceMotion {
                // No lift: the square appears already lifted, with a fade.
                visible = false; lifted = true
                withAnimation(.easeOut(duration: 0.3)) { visible = true }
                return
            }
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.spring(response: 0.6, dampingFraction: 0.72)) { lifted = true }
        }
    }

    private var ground: some View {
        ZStack {
            LinearGradient(colors: [c(Self.topLeft), c(Self.bottomLeft)], startPoint: .top, endPoint: .bottom)
            LinearGradient(colors: [c(Self.topRight), c(Self.bottomRight)], startPoint: .top, endPoint: .bottom)
                .mask(LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: .trailing))
        }
        .clipShape(RoundedRectangle(cornerRadius: 70, style: .continuous))
    }

    private func square(_ k: CGFloat) -> some View {
        let side = Self.face.width * k, radius = 56 * k
        return ZStack {
            // Soft glow under the square, brighter once it is lifted.
            RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Color(red: 0xE0 / 255, green: 0xA8 / 255, blue: 0x3C / 255).opacity(0.45))
                .frame(width: side, height: side).offset(y: side * 34 / 48).blur(radius: 9 / 200 * 1024 * k).opacity(lifted ? 1 : 0)
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0xf3 / 255, green: 0xcf / 255, blue: 0x63 / 255), Color(red: 0xc8 / 255, green: 0x97 / 255, blue: 0x2d / 255)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: side, height: side)
            RoundedRectangle(cornerRadius: radius - 1, style: .continuous).strokeBorder(.white.opacity(0.35), lineWidth: 1).frame(width: side - 1, height: side - 1)
        }
        .frame(width: side, height: side)
    }
}
