import SwiftUI
import DiskCleanerCore

struct OverviewScreen: View {
    @ObservedObject var model: CleanerModel
    @ObservedObject var presentation: CleanerPresentation
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Phase: Equatable { case scanning, empty, saved }
    private var phase: Phase {
        if model.scanning && !model.viewingSavedDuringScan { return .scanning }
        return model.hasSnapshot ? .saved : .empty
    }
    var body: some View {
        // Empty, scanning and saved states fade through; each arrives with its figures
        // already final. The saved scan, the payoff, also rises 8 pt as it arrives.
        ZStack(alignment: .topLeading) {
            switch phase {
            case .scanning: ScanningState(model: model).transaction { $0.animation = nil }.transition(.fadeThrough)
            case .empty: EmptyInventory(model: model).transaction { $0.animation = nil }.transition(.fadeThrough)
            case .saved:
                VStack(alignment: .leading, spacing: 0) {
                    bannerSlot
                    VStack(alignment: .leading, spacing: 22) {
                        CapacityOverview(model: model)
                        HStack(alignment: .top, spacing: 20) {
                            CleanupEstimate(model: model, presentation: presentation).frame(maxWidth: .infinity, alignment: .topLeading)
                            VStack(alignment: .leading, spacing: 20) {
                                GrowthSection(model: model)
                                OlderFilesSection(model: model)
                                RecentCleanup(model: model)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                }
                // The banner slides down from the top when a scan starts over a saved scan;
                // when the scan ends it fades and its space closes on the same spring, so
                // the content rises instead of dropping 62 pt at once. Figures change directly.
                .animation(CleanerMotion.layout(CleanerMotion.disclosure, reduceMotion: reduceMotion), value: model.scanning)
                .transaction { $0.animation = nil }
                .transition(.asymmetric(
                    insertion: AnyTransition.offset(y: reduceMotion ? 0 : 8).combined(with: .opacity).animation(CleanerMotion.fadeIn),
                    removal: AnyTransition.opacity.animation(CleanerMotion.fadeOut)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .animation(CleanerMotion.fadeIn, value: phase)
    }
    @ViewBuilder private var bannerSlot: some View {
        if let exit = motionFrame?.bannerExit {
            FractionalHeight(fraction: exit.open) {
                ScanningBanner(model: exit.source).padding(.bottom, 22).opacity(exit.opacity)
            }.clipped()
        } else if model.scanning {
            ScanningBanner(model: model).padding(.bottom, 22)
                .transition(.asymmetric(
                    insertion: reduceMotion ? AnyTransition.opacity : AnyTransition.move(edge: .top).combined(with: .opacity),
                    removal: AnyTransition.opacity.animation(CleanerMotion.bannerOut)))
        }
    }
}

struct EmptyInventory: View {
    @ObservedObject var model: CleanerModel
    @State private var volume: BootVolumeFigure?
    init(model: CleanerModel) {
        self.model = model
        _volume = State(initialValue: model.isFixture ? .example : BootVolumeFigure.measure())
    }
    var body: some View {
        FirstRunPage(title: "Overview", subtitle: "Choose a folder to see what takes up space.") {
            if let volume {
                FirstRunCard {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(volume.availableText).font(.system(size: 44, weight: .bold)).monospacedDigit()
                        Text("free on \(volume.name)").font(.system(size: 16, weight: .medium)).foregroundStyle(Paint.secondary)
                    }
                    Text("Measured now").font(.system(size: 12)).foregroundStyle(Paint.secondary).padding(.top, 6)
                }
            }
            ChooseFolderCard(model: model, helper: "Starts in \(chooserStartText(model)). Disk Cleaner only reads sizes. Nothing moves until you tick items and confirm.", showsScanSettings: true)
        }
        .onChange(of: model.screen) { _, screen in
            if screen == .overview, !model.isFixture { volume = BootVolumeFigure.measure() }
        }
    }
}

/// Core reports no traversal progress, so no amount or current path is shown.
struct ScanningState: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Scanning \(model.isFixture ? model.scopeTitle : model.scanRoot?.lastPathComponent ?? "folder")").font(.system(size: 20, weight: .semibold))
            Text("Reading folders. Sizes appear when the scan finishes.").foregroundStyle(Paint.secondary)
            ProgressView().progressViewStyle(.linear).tint(.gray).padding(.top, 4)
            HStack {
                Text("Reading folders under \(model.scanRoot?.path ?? "the chosen folder")").lineLimit(1).truncationMode(.middle)
                Spacer()
                Text("Progress amount not shown")
            }.font(.system(size: 11)).foregroundStyle(Paint.secondary)
            if model.previousSnapshotAvailable {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Previous saved scan stays available")
                        Text("\(model.scopeTitle) · \(dateText(model.scanDate, time: true))").font(.system(size: 11)).foregroundStyle(Paint.secondary)
                    }
                    Spacer()
                    Button("View saved scan") { model.viewingSavedDuringScan = true }.buttonStyle(NeutralStyle(compact: true))
                }.padding(.horizontal, 14).padding(.vertical, 9).background { PanelSurface(radius: 9) }
            }
            Button("Cancel scan") { model.cancelScan() }.buttonStyle(GhostStyle()).padding(.top, 6)
            Text("Cancelling stops reading. Nothing is changed or removed on disk.").font(.system(size: 12)).foregroundStyle(Paint.secondary)
        }
        .frame(maxWidth: 560, alignment: .leading).frame(maxWidth: .infinity).padding(.top, 70)
    }
}

struct ScanningBanner: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(.gray)
            Text("Scanning \(model.scanRoot?.lastPathComponent ?? "folder")… Showing the previous saved scan.")
            Spacer()
            Button("Show progress") { model.viewingSavedDuringScan = false }.buttonStyle(NeutralStyle(compact: true))
            Button("Cancel scan") { model.cancelScan() }.buttonStyle(NeutralStyle(compact: true))
        }.padding(.horizontal, 14).padding(.vertical, 8).background { PanelSurface(radius: 9) }
    }
}

struct CapacityStrip: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 2) {
                if model.isFixture {
                    ForEach(model.items) { item in RoundedRectangle(cornerRadius: 3).fill(Paint.hue(item.hue)).frame(width: width(item.bytes ?? 0, proxy.size.width)) }
                } else if let used = model.used {
                    RoundedRectangle(cornerRadius: 3).fill(Paint.slate).frame(width: max(0, proxy.size.width - 2) * min(1, Double(used) / Double(max(model.total ?? 1, 1))))
                }
                if let residual = model.residual, residual > 0 { Hatch().frame(width: width(residual, proxy.size.width)).clipShape(RoundedRectangle(cornerRadius: 3)) }
                if let free = model.available { RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.25)).frame(width: width(free, proxy.size.width)) }
            }
        }.frame(height: 16).transaction { $0.animation = nil }
    }
    private func width(_ amount: Int64, _ full: CGFloat) -> CGFloat {
        let count = model.isFixture ? model.items.count + 2 : 2
        return max(0, (full - CGFloat(count - 1) * 2) * Double(amount) / Double(max(model.total ?? 1, 1)))
    }
}

struct CapacityOverview: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isFixture ? model.scopeTitle : "Disk space").font(.system(size: 22, weight: .semibold))
                    Text("\(bytes(model.total)) total · last scan \(dateText(model.scanDate, time: true))").foregroundStyle(Paint.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(bytes(model.available)).font(.system(size: 38, weight: .semibold)).monospacedDigit()
                    Text("available").foregroundStyle(Paint.secondary)
                }
            }
            HStack { Text("Used: \(bytes(model.used)) of \(bytes(model.total))"); Spacer(); Text("\(bytes(model.available)) available") }.font(.system(size: 12)).padding(.top, 2)
            CapacityStrip(model: model)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 28), count: 3), spacing: 12) {
                ForEach(model.items.prefix(model.isFixture ? 5 : 8)) { item in
                    HStack(spacing: 9) {
                        RoundedRectangle(cornerRadius: 2).fill(Paint.hue(item.hue)).frame(width: 9, height: 9)
                        Text(item.name).lineLimit(1); Spacer()
                        Text(item.sizeHidden ? "Size not shown" : bytes(item.bytes)).monospacedDigit().foregroundStyle(item.sizeHidden ? Paint.secondary : Color(white: 0.94))
                    }
                }
                if let residual = model.residual {
                    HStack(spacing: 9) { Hatch().frame(width: 9, height: 9); Text("Not accounted for"); Spacer(); Text(bytes(residual)).monospacedDigit() }
                }
            }.padding(.vertical, 5)
            Rule()
            if model.isFixture {
                Text("**Not accounted for** is 482 GB used − 470 GB categorized. What it contains is unknown.").foregroundStyle(Paint.secondary)
            } else {
                Text("Volume capacity is for the whole disk. Folder sizes cover \(model.root?.path ?? "the chosen folder") only, are estimates, and may include shared file storage more than once.").foregroundStyle(Paint.secondary)
            }
            HStack(alignment: .center, spacing: 12) {
                Text(model.coverageErrors.isEmpty ? "Folder sizes are scan estimates; unreadable areas remain unknown." : model.isFixture ? model.coverageErrors[0] : "\(model.coverageErrors.count) folders could not be read; affected sizes are unknown.").foregroundStyle(Paint.secondary)
                Button("Browse files") { model.screen = .browse }.buttonStyle(NeutralStyle(compact: true))
            }
            ScanControls(model: model).padding(.top, 4)
        }.font(.system(size: 13))
    }
}

struct CleanupEstimate: View {
    @ObservedObject var model: CleanerModel
    @ObservedObject var presentation: CleanerPresentation
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.pageScroller) private var scroller
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var scopeText: String {
        model.isFixture ? "Covers unused package files in the package cache: about 6.2 GB of the 15 GB total. Files estimated as in use (8.8 GB) are kept. Whether removed files can be restored is unknown." : "Inventory age and folder size do not authorize removal. Cleanup is limited to established app-owned rules; none are enabled."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CleanupEstimateBody(demo: model.isFixture)
            Rule()
            Button {
                let opening = !presentation.scopeOpen
                let spring = CleanerMotion.layout(CleanerMotion.disclosure, reduceMotion: reduceMotion)
                withAnimation(spring) { presentation.scopeOpen.toggle() }
                // The card sits at the bottom of the default window: once the opened layout
                // exists (one run loop later), scroll the least that shows its end, on the same spring.
                if opening, let scroller {
                    DispatchQueue.main.async { withAnimation(spring) { scroller.scrollTo("scope-end", anchor: nil) } }
                }
            } label: {
                HStack {
                    Text("Scope and estimate")
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).rotationEffect(.degrees(90 * (motionFrame?.disclosureOpen ?? (presentation.scopeOpen ? 1 : 0))))
                }.foregroundStyle(Color(white: 0.82)).padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 43).contentShape(Rectangle())
            }.buttonStyle(WholeRowStyle())
            // The explanation owns a clipped viewport below its header, so a close
            // or rapid reversal never carries text through the header.
            VStack(alignment: .leading, spacing: 0) {
                if let open = motionFrame?.disclosureOpen {
                    FractionalHeight(fraction: open) { scopeBody.opacity(open).offset(y: -6 * (1 - open)) }
                } else if presentation.scopeOpen {
                    scopeBody.transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : -6)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .clipped()
            .id("scope-end")
        }
        .background { PanelSurface() }.clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .animation(CleanerMotion.layout(CleanerMotion.disclosure, reduceMotion: reduceMotion), value: presentation.scopeOpen)
    }
    private var scopeBody: some View {
        Text(scopeText)
            .foregroundStyle(Paint.secondary).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.bottom, 16)
    }
}

struct CleanupEstimateBody: View {
    let demo: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Make room for work").font(.system(size: 16, weight: .semibold))
            if demo {
                Text("Package cache · estimated from the 4 Nov, 10:20 scan").font(.system(size: 12)).foregroundStyle(Paint.secondary)
                VStack(spacing: 0) {
                    Rule(); ValueRow(title: "Total cache", value: "15 GB"); Rule()
                    ValueRow(title: "Estimated unused", value: "6.2 GB", marker: Paint.teal); Rule()
                    ValueRow(title: "Estimated used and retained before cleanup", value: "8.8 GB", marker: Color.white.opacity(0.25))
                }
                GeometryReader { proxy in
                    HStack(spacing: 2) { RoundedRectangle(cornerRadius: 3).fill(Paint.teal).frame(width: proxy.size.width * 0.413); RoundedRectangle(cornerRadius: 3).fill(.white.opacity(0.25)) }
                }.frame(height: 8).transaction { $0.animation = nil }
                Text("These are estimates of what the cache contains. The change in available space is measured afterwards and may differ.")
                Text("Permanently removed cache files may need to be downloaded again, and future installs may need network access.")
            } else {
                Text("No cleanup rule is enabled").fontWeight(.medium)
                Text("This version can read folders and record cleanup requests. No verified cleanup operation is available, so it will not remove files.")
            }
            HStack(spacing: 12) {
                Button(demo ? "Clear unused packages" : "Clean up") {}.buttonStyle(GhostStyle()).disabled(true)
                Text(demo ? "Preview only · no cleanup runs in this concept" : "Unavailable until a cleanup rule is enabled.").font(.system(size: 11)).foregroundStyle(Paint.secondary)
            }
        }.font(.system(size: 12)).foregroundStyle(Color(white: 0.82)).padding(17)
    }
}

struct GrowthSection: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Heading(title: model.comparisonDate.map { "Growth since \(dateText($0, time: true))" } ?? "Growth")
            GroupCard {
                if model.isFixture {
                    HStack { Spacer(); Text("Now").frame(width: 76, alignment: .trailing); Text("Change").frame(width: 76, alignment: .trailing) }
                        .font(.system(size: 11)).foregroundStyle(Paint.secondary).padding(.horizontal, 16).frame(height: 28)
                    GrowthRow(name: "Xcode build data", now: "25 GB", delta: "+8.2 GB")
                    GrowthRow(name: "Package cache", now: "15 GB", delta: "+4.6 GB")
                    GrowthRow(name: "Preview builds", now: "3.8 GB", delta: "+1.2 GB")
                } else {
                    let changes = model.items.filter { $0.growth != nil && !$0.sizeHidden }.sorted { ($0.growth ?? 0) > ($1.growth ?? 0) }
                    if changes.isEmpty { Text("Another comparable scan is needed to show growth. Incomplete folder totals cannot prove a change.").foregroundStyle(Paint.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                    ForEach(changes) { item in GrowthRow(name: item.name, now: bytes(item.bytes), delta: (item.growth ?? 0) > 0 ? "+\(bytes(item.growth))" : bytes(item.growth)) }
                }
            }
        }
    }
}
struct GrowthRow: View {
    let name: String
    let now: String
    let delta: String
    var body: some View {
        HStack { Text(name).lineLimit(1); Spacer(); Text(now).frame(width: 76, alignment: .trailing); Text(delta).frame(width: 76, alignment: .trailing) }
            .monospacedDigit().padding(.horizontal, 16).frame(minHeight: 43)
    }
}

struct OlderFilesSection: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Heading(title: model.isFixture ? "Large and unchanged" : "Large files to look through")
            GroupCard {
                if model.oldItems.isEmpty { Text("No dated items recorded yet.").foregroundStyle(Paint.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
                ForEach(model.oldItems.prefix(model.isFixture ? 2 : 5)) { item in
                    Button { model.reveal(inBrowse: item.path) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) { Text(item.name).lineLimit(1); Text("Last changed \(dateText(item.modified))").font(.system(size: 11)).foregroundStyle(Paint.secondary) }
                            Spacer(); Text(bytes(item.bytes)).monospacedDigit(); RowChevron()
                        }.padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(WholeRowStyle())
                }
            }
        }
    }
}

struct RecentCleanup: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Heading(title: "Recent cleanup")
            GroupCard {
                if let job = model.isFixture ? model.jobs.last : model.jobs.first {
                    Button { model.selectJob(job) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(dateText(job.date, time: true)) · Agent request")
                                Text("Available space \(bytes(job.before)) → \(bytes(job.after))\(job.before.flatMap { before in job.after.map { " (\($0 - before >= 0 ? "+" : "")\(bytes($0 - before)))" } } ?? "")").font(.system(size: 11)).foregroundStyle(Paint.secondary)
                            }
                            Spacer(); RowChevron()
                        }.padding(.horizontal, 16).frame(minHeight: 48).contentShape(Rectangle())
                    }.buttonStyle(WholeRowStyle())
                } else { Text("No cleanup requests yet.").foregroundStyle(Paint.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
}
