import SwiftUI
import AppKit
import DiskCleanerCore

struct BrowseScreen: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        let ready = model.hasSnapshot && model.currentPath != nil
        ZStack(alignment: .topLeading) {
            if ready {
                BrowseList(model: model).transition(.fadeThrough)
            } else {
                FirstRunPage(title: model.scanning ? "Scan in progress" : "Browse files",
                             subtitle: model.scanning ? "Files appear here when the scan finishes." : "No scan yet. Choose a folder to browse it by size.") {
                    if !model.scanning {
                        ChooseFolderCard(model: model, helper: "Starts in \(chooserStartText(model)). Same folder chooser as Overview.")
                    }
                }.transition(.fadeThrough)
            }
        }
        .animation(CleanerMotion.fadeIn, value: ready)
    }
}

/// Browse files. The header, the folder card and the inspector stay where they are;
/// only their contents swap. The Trash review and outcome replace the list column
/// in place, over the list, which stays laid out and unscrolled underneath, so
/// Cancel returns to the exact position and selection.
struct BrowseList: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.pageScroller) private var scroller
    @Environment(\.pageViewportHeight) private var viewport
    /// Top of the list column in the page's visible area.
    @State private var columnTop: CGFloat = 0
    /// Where the review starts inside the column, fixed when it opens, so it is in view
    /// even when the list was scrolled down to the checked bar.
    @State private var stageTop: CGFloat = 0
    var body: some View {
        let swap = motionFrame?.stage
        let showingList = model.browseStage == .list
        let listSource = (swap != nil && !showingList) ? swap!.outgoing : model
        let stageSource = (swap != nil && showingList) ? swap!.outgoing : model
        let listOpacity = swap.map { showingList ? $0.in : 1 - $0.out } ?? (showingList ? 1 : 0)
        VStack(alignment: .leading, spacing: 14) {
            BrowseHeader(model: model)
            HStack(alignment: .top, spacing: 20) {
                ZStack(alignment: .topLeading) {
                    BrowseListColumn(model: listSource)
                        .opacity(listOpacity)
                        .allowsHitTesting(showingList).accessibilityHidden(!showingList)
                        .animation(showingList ? CleanerMotion.fadeIn : CleanerMotion.fadeOut, value: showingList)
                    Group {
                        if let swap {
                            BrowseStagePanel(model: stageSource, availableHeight: availableHeight)
                                .opacity(showingList ? 1 - swap.out : swap.in)
                        } else {
                            ZStack(alignment: .topLeading) {
                                switch model.browseStage {
                                case .review: BrowseStagePanel(model: model, availableHeight: availableHeight).id(BrowseStagePanel.Kind.review).transition(.fadeThrough)
                                case .outcome: BrowseStagePanel(model: model, availableHeight: availableHeight).id(BrowseStagePanel.Kind.outcome).transition(.fadeThrough)
                                case .list: EmptyView()
                                }
                            }
                            .animation(CleanerMotion.fadeIn, value: model.browseStage)
                        }
                    }
                    .padding(.top, stageTop)
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("page")).minY } action: { columnTop = $0 }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                FileInspector(model: model).frame(width: 292)
            }
        }
        .onChange(of: model.browseStage) { old, _ in
            if old == .list { stageTop = max(0, 12 - columnTop) }
        }
        .onChange(of: model.navigationCount) { _, _ in
            // Restore the row we navigated through, or start at the top; in the same update
            // and without animation, so the arriving rows fade in already in place.
            if let target = model.scrollTarget { scroller?.jump(to: target, anchor: .center) } else { scroller?.jump(to: "browse-top", anchor: .top) }
        }
    }
    private var availableHeight: CGFloat {
        guard viewport > 0 else { return 10_000 }
        return max(240, viewport - max(columnTop + stageTop, 12) - 16)
    }
}

/// Folder card, checked bar and notes: the content the Trash review replaces.
struct BrowseListColumn: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FolderContents(model: model)
            CheckedBar(model: model)
            Text("Age does not authorize anything. Inspecting a row changes nothing; only checked rows go to review.")
                .font(.system(size: 12)).foregroundStyle(Paint.secondary)
            if let note = model.checkDisabledNote { Text(note).font(.system(size: 12)).foregroundStyle(Paint.warning) }
            if model.atRoot && model.search.isEmpty && !model.oldItems.isEmpty { BrowseOlderFiles(model: model).padding(.top, 8).transition(.fadeThrough) }
        }
        // The card resizes to the arriving rows and everything below follows on one spring.
        .animation(CleanerMotion.layout(CleanerMotion.navigate, reduceMotion: reduceMotion), value: model.currentPath)
    }
}

/// The review or the outcome, in the list column's place.
struct BrowseStagePanel: View {
    enum Kind: Hashable { case review, outcome }
    @ObservedObject var model: CleanerModel
    let availableHeight: CGFloat
    var body: some View {
        switch model.browseStage {
        case .outcome: TrashOutcomeScreen(model: model, availableHeight: availableHeight)
        default: TrashReviewScreen(model: model, availableHeight: availableHeight)
        }
    }
}

/// Holds still during the Trash review, but visibly disabled (native look), with its back
/// chevron faded out so the review's own back is the only one, and the search field
/// unfocused without a caret.
struct BrowseHeader: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.motionFrame) private var motionFrame
    @FocusState private var searchFocused: Bool
    private var backOpacity: Double {
        let list = model.listNavigable
        if let swap = motionFrame?.stage { return list ? swap.in : 1 - swap.out }
        return list ? 1 : 0
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Button { model.back() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconStyle()).disabled(!model.canGoBack).help("Back to the enclosing folder")
                    .accessibilityLabel("Back")
                    .opacity(backOpacity).accessibilityHidden(!model.listNavigable)
                    .animation(model.listNavigable ? CleanerMotion.fadeIn : CleanerMotion.fadeOut, value: model.listNavigable)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Breadcrumbs(model: model)
                    }
                    ScanControls(model: model)
                }
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Paint.secondary)
                    TextField("Search this folder and below", text: $model.search).textFieldStyle(.plain).focused($searchFocused)
                    if !model.search.isEmpty {
                        Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Paint.secondary) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 11).frame(width: 236, height: 32)
                    .background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.09)))
            }
            .id("browse-top")
            HStack(spacing: 10) {
                Text("Click a row to inspect or open it · use the checkbox to include it for Trash")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(white: 0.82))
                Spacer()
                Picker("Sort", selection: $model.sort) {
                    Text("Size").tag(InventorySort.size); Text("Name").tag(InventorySort.name); Text("Modified").tag(InventorySort.modified)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                Button {
                    model.direction = model.direction == .descending ? .ascending : .descending
                } label: { Image(systemName: model.direction == .descending ? "arrow.down" : "arrow.up") }
                    .buttonStyle(IconStyle(size: 26))
                    .help(model.direction == .descending ? "Largest, last or newest first" : "Smallest, first or oldest first")
                    .accessibilityLabel(model.direction == .descending ? "Descending" : "Ascending")
            }
        }
        .disabled(!model.listNavigable)
        .onChange(of: model.screen) { _, screen in if screen != .browse { searchFocused = false } }
        .onChange(of: model.browseStage) { _, _ in searchFocused = false }
    }
}

/// The trail grows or shrinks at its end, in step with the list: an arriving crumb fades
/// in with the arriving rows, a leaving one fades out with the leaving rows.
struct Breadcrumbs: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let current = model.breadcrumbs
        let swap = motionFrame?.folder
        let before = swap?.outgoing.breadcrumbs ?? current
        let leaving = before.filter { crumb in !current.contains { $0.path == crumb.path } }
        HStack(spacing: 4) {
            if model.isFixture { Text("Macintosh HD").fontWeight(.semibold).foregroundStyle(Paint.secondary); Text("/").foregroundStyle(Paint.secondary) }
            ForEach(Array(current.enumerated()), id: \.element.path) { index, crumb in
                let arriving = swap != nil && !before.contains { $0.path == crumb.path }
                crumbView(crumb, first: index == 0, last: crumb.path == current.last?.path)
                    .opacity(arriving ? swap!.in : 1)
                    .offset(x: arriving ? 6 * (1 - swap!.in) : 0)
                    // Same direction as the rows: on back the leaving crumb drifts trailing.
                    .transition(model.folderArrivesWithPage ? .identity : .navigation(step: model.navigationStep == 0 ? 1 : model.navigationStep, reduceMotion: reduceMotion))
            }
            if let swap {
                ForEach(leaving, id: \.path) { crumb in
                    crumbView(crumb, first: false, last: false).opacity(1 - swap.out)
                        .offset(x: -CGFloat(swap.step.signum()) * CleanerMotion.leaveTravel * swap.out)
                }
            }
        }
        .font(.system(size: 14))
        .animation(CleanerMotion.layout(CleanerMotion.navigate, reduceMotion: reduceMotion), value: model.currentPath)
    }
    private func crumbView(_ crumb: InventoryBreadcrumb, first: Bool, last: Bool) -> some View {
        HStack(spacing: 4) {
            if !first { Text("/").foregroundStyle(Paint.secondary) }
            Button { model.navigate(crumb.path) } label: {
                Text(model.displayName(crumb.path)).fontWeight(.semibold)
                    .foregroundStyle(last ? Color(white: 0.96) : Paint.secondary)
                    .animation(CleanerMotion.fadeIn, value: last)
                    .lineLimit(1)
            }.buttonStyle(.plain).disabled(last).pointingCursor()
        }
    }
}

/// One folder card that stays put and resizes to the arriving rows; only the rows swap.
struct FolderContents: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let swap = motionFrame?.folder
        VStack(alignment: .leading, spacing: 6) {
            if !model.search.isEmpty { Text("\(model.visibleItems.count) matches in \(model.displayName(model.currentPath ?? "")) and below").font(.system(size: 12)).foregroundStyle(Paint.secondary) }
            GroupCard {
                ArrivingSized(current: model.currentPath ?? "", pinned: swap?.height) {
                    if let swap {
                        let side = CGFloat(swap.step.signum())
                        FolderRows(model: swap.outgoing)
                            .opacity(1 - swap.out).offset(x: -side * CleanerMotion.leaveTravel * swap.out)
                            .layoutValue(key: MotionStateKey.self, value: swap.outgoing.currentPath ?? "")
                        FolderRows(model: model)
                            .opacity(swap.in).offset(x: side * CleanerMotion.arriveTravel * (1 - swap.in))
                            .layoutValue(key: MotionStateKey.self, value: model.currentPath ?? "")
                    } else {
                        FolderRows(model: model)
                            .transaction { $0.animation = nil }
                            .layoutValue(key: MotionStateKey.self, value: model.currentPath ?? "")
                            .id(model.currentPath ?? "")
                            .transition(model.folderArrivesWithPage ? .identity : .navigation(step: model.navigationStep, reduceMotion: reduceMotion))
                    }
                }
            }
        }
    }
}

struct FolderRows: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        let rows = model.visibleItems
        let largest = rows.compactMap { $0.sizeHidden ? nil : $0.bytes }.max() ?? 1
        VStack(spacing: 0) {
            ForEach(rows) { item in
                BrowseRow(model: model, item: item, largest: largest, showPath: !model.search.isEmpty)
                    .id(item.path)
                if item.id != rows.last?.id { Rule().padding(.leading, 40) }
            }
            if rows.isEmpty { Text(model.search.isEmpty ? "This folder has no recorded items." : "No matching items.").foregroundStyle(Paint.secondary).padding(16).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }
}

struct BrowseRow: View {
    @ObservedObject var model: CleanerModel
    let item: FileItem
    let largest: Int64
    let showPath: Bool
    /// Extra fill for the one-time locating cue after a jump from Overview.
    @State private var locate = 0.0
    @Environment(\.motionFrame) private var motionFrame
    /// Highlight strength; a preview frame may pin it part-way along the selection spring.
    private var highlight: Double {
        let selected = model.selectedItem == item.path
        guard let pinned = motionFrame?.selection else { return selected ? 1 : 0 }
        return selected ? pinned.progress : item.path == pinned.from ? 1 - pinned.progress : 0
    }
    var body: some View {
        let selected = model.selectedItem == item.path
        HStack(spacing: 0) {
            TrashCheckbox(name: item.name, checked: model.isChecked(item.path), enabled: model.isCheckable(item)) { model.toggleChecked(item.path) }
            Button { model.open(item) } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).lineLimit(1)
                        Text(subtitle).font(.system(size: 11)).foregroundStyle(Paint.secondary).lineLimit(1).truncationMode(.middle)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if item.coverage == .partial { Text("Partial coverage").font(.system(size: 11)).foregroundStyle(Paint.secondary) }
                    if item.coverage == .unavailable { Text("Could not be read").font(.system(size: 11)).foregroundStyle(Paint.secondary) }
                    if !item.sizeHidden, model.atRoot, model.search.isEmpty {
                        RelativeSizeBar(fraction: Double(item.bytes ?? 0) / Double(max(largest, 1)), color: Paint.hue(item.hue)).frame(width: 90, height: 5)
                    }
                    Text(item.sizeHidden ? "–" : bytes(item.bytes)).monospacedDigit().foregroundStyle(item.sizeHidden ? Paint.secondary : Color(white: 0.94))
                        .frame(width: 66, alignment: .trailing)
                    if item.directory { RowChevron() } else { Color.clear.frame(width: 12, height: 1) }
                }
                .padding(.trailing, 14).frame(minHeight: 44).contentShape(Rectangle())
            }.buttonStyle(WholeRowStyle())
        }
        .background { Color.white.opacity(0.10 * highlight + locate).animation(CleanerMotion.selection, value: selected) }
        .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.56 * highlight)).frame(width: 2).animation(CleanerMotion.selection, value: selected) }
        .task(id: model.revealCount) {
            // Jump from Overview: the row arrives a little brighter and settles to the
            // normal inspected fill, so the eye finds it. Once per jump.
            guard model.revealedPath == item.path else { return }
            model.consumeReveal()
            var instant = Transaction(); instant.disablesAnimations = true
            withTransaction(instant) { locate = 0.12 }
            try? await Task.sleep(for: .milliseconds(230))
            withAnimation(.easeOut(duration: 0.6)) { locate = 0 }
        }
    }
    private var subtitle: String {
        var parts: [String] = []
        if showPath { parts.append(item.path) }
        if item.sizeHidden && item.directory { parts.append("Folder · size not shown") }
        else if item.sizeHidden { parts.append("Size not shown") }
        else if let modified = item.modified { parts.append("Changed \(dateText(modified))") }
        else { parts.append(item.directory ? "Folder" : "File") }
        return parts.joined(separator: " · ")
    }
}

/// Always present, so the layout never jumps. Count and size are figures and change
/// directly; only the label colour and the Review button's outline ease.
struct CheckedBar: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        let none = model.checkedPaths.isEmpty
        HStack(spacing: 10) {
            Text(none ? "Nothing checked for Trash" : "\(model.checkedPaths.count) checked for Trash · \(bytes(model.checkedTotal))")
                .foregroundStyle(none ? Paint.secondary : Color(white: 0.94))
                .animation(CleanerMotion.release, value: none)
            Spacer()
            Button("Clear checks") { model.clearChecks() }.buttonStyle(NeutralStyle(compact: true)).disabled(none || model.trashBusy)
            Button("Review for Trash…") { model.requestTrashReview() }.buttonStyle(GhostStyle())
                .disabled(none || !model.canCheckForTrash)
                .animation(CleanerMotion.release, value: none)
            // Always laid out, so the buttons beside it never shift when it appears.
            ProgressView().controlSize(.small).tint(.gray).opacity(model.trashBusy ? 1 : 0).accessibilityHidden(!model.trashBusy)
        }.padding(.horizontal, 14).frame(minHeight: 46).background { PanelSurface(radius: 9) }
    }
}

struct BrowseOlderFiles: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Heading(title: model.isFixture ? "Large and unchanged" : "Large files to look through")
            GroupCard {
                ForEach(model.oldItems) { item in
                    Button { model.reveal(inBrowse: item.path) } label: {
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).lineLimit(1)
                                Text(item.path).font(.system(size: 11)).foregroundStyle(Paint.secondary).lineLimit(1).truncationMode(.middle)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text("Changed \(dateText(item.modified))").font(.system(size: 11)).foregroundStyle(Paint.secondary)
                            Text(bytes(item.bytes)).monospacedDigit().frame(width: 66, alignment: .trailing)
                            RowChevron()
                        }.padding(.horizontal, 14).frame(minHeight: 46).contentShape(Rectangle())
                    }.buttonStyle(WholeRowStyle())
                }
            }
        }
    }
}

/// The inspector card holds still: every slot keeps its space (two-line name, two-line
/// path, fixed size line, facts that wrap keep two lines), so its height never changes.
/// Selecting another row in the same folder changes the values directly. Only when the
/// inspected item changes because of navigation do the values fade through, in step with
/// the rows; titles, rules and buttons stay drawn. While the Trash review holds the list
/// column, the inspector is disabled and cannot navigate the hidden list.
struct FileInspector: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.motionFrame) private var motionFrame
    var body: some View {
        let swap = motionFrame?.folder
        ZStack(alignment: .topLeading) {
            if let swap, swap.outgoing.selectedItem != model.selectedItem {
                InspectorContent(model: swap.outgoing, item: swap.outgoing.selected, layer: .values).opacity(1 - swap.out)
                InspectorContent(model: model, item: model.selected, layer: .values).opacity(swap.in)
            } else {
                ZStack(alignment: .topLeading) {
                    InspectorContent(model: model, item: model.selected, layer: .values)
                        .transaction { $0.animation = nil }
                        .id(model.navigationCount)
                        .transition(model.folderArrivesWithPage ? .identity : .fadeThrough)
                }
                .animation(CleanerMotion.fadeIn, value: model.navigationCount)
            }
            // Drawn above the values so its buttons take clicks; its value slots are empty.
            InspectorContent(model: model, item: model.selected, layer: .chrome)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
        .background { PanelSurface(raised: true) }
        .disabled(!model.listNavigable)
    }
}

struct InspectorContent: View {
    /// The card is drawn as two aligned layers: `chrome` (titles, rules, buttons, note),
    /// which never fades, and `values` (name, path, size, fact values), which may.
    enum Layer { case chrome, values }
    @ObservedObject var model: CleanerModel
    let item: FileItem?
    let layer: Layer
    var body: some View {
        let values = layer == .values
        VStack(alignment: .leading, spacing: 0) {
            Text(item == nil ? "Nothing inspected" : "Inspecting").font(.system(size: 11)).foregroundStyle(Paint.secondary).padding(.bottom, 6)
                .shown(!values)
            Text(item?.name ?? "Select a file or folder").font(.system(size: 16, weight: .semibold)).lineLimit(2, reservesSpace: true)
                .shown(values)
            Group {
                if let item {
                    Text(item.path).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(white: 0.78))
                        .truncationMode(.middle).textSelection(.enabled).help(item.path)
                } else {
                    Text("Its size, full path and scan coverage appear here.").font(.system(size: 12)).foregroundStyle(Paint.secondary)
                }
            }
            .lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            .shown(values)
            Text(item == nil ? " " : item!.sizeHidden ? "Size not shown" : bytes(item!.bytes))
                .font(.system(size: item?.sizeHidden == false ? 30 : 18, weight: .semibold)).monospacedDigit()
                .foregroundStyle(item?.sizeHidden == false ? Color(white: 0.96) : Paint.secondary)
                .frame(height: 40, alignment: .leading).padding(.vertical, 8)
                .shown(values)
            Group {
                InspectorFact(title: "Last changed", value: item.map { dateText($0.modified) } ?? " ", layer: layer)
                InspectorFact(title: "Coverage", value: item.map(coverage) ?? " ", lines: 2, layer: layer)
                InspectorFact(title: "Comparison", value: item.map { $0.growth.map { "\($0 > 0 ? "+" : "")\(bytes($0)) since \(dateText(model.comparisonDate, time: true))" } ?? "No earlier comparison available" } ?? " ", layer: layer)
                InspectorFact(title: "Checked for Trash", value: item.map { model.isChecked($0.path) ? "Yes" : model.isCheckable($0) ? "No" : "No · cannot be checked (\(reason($0)))" } ?? " ", lines: 2, layer: layer)
                HStack(spacing: 8) {
                    Button("Show in Finder") { if let item { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: item.path)]) } }
                        .buttonStyle(NeutralStyle()).disabled(model.isFixture || item == nil)
                    // Always laid out, so the card keeps its height for files and folders.
                    let opensFolder = item.map { $0.directory && $0.path != model.currentPath } ?? false
                    Button("Open folder") { if let item { model.open(item) } }.buttonStyle(NeutralStyle())
                        .disabled(!opensFolder).opacity(opensFolder ? 1 : 0).accessibilityHidden(!opensFolder)
                }.padding(.top, 14)
                .shown(!values)
            }
            .opacity(item == nil ? 0 : 1)
            if model.isFixture { Text("Show in Finder is off for example data.").font(.system(size: 11)).foregroundStyle(Paint.secondary).padding(.top, 6).shown(!values) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    private func coverage(_ item: FileItem) -> String {
        switch item.coverage {
        case .complete: "Read in the \(dateText(model.scanDate, time: true)) scan"
        case .partial: "Partial · some contents could not be read, so no folder total is shown"
        case .unavailable: "Unavailable · size unknown"
        }
    }
    private func reason(_ item: FileItem) -> String {
        if item.coverage != .complete { return "coverage incomplete" }
        if model.stale { return "scan out of date" }
        return "scan this folder in this session first"
    }
}

private extension View {
    /// Keeps the view laid out in both inspector layers; draws it only in its own layer.
    func shown(_ visible: Bool) -> some View { opacity(visible ? 1 : 0).accessibilityHidden(!visible).allowsHitTesting(visible) }
}

struct InspectorFact: View {
    let title: String
    let value: String
    /// Two lines only for the facts that wrap (coverage and the Trash check).
    var lines = 1
    var layer: InspectorContent.Layer = .chrome
    var body: some View {
        let values = layer == .values
        VStack(alignment: .leading, spacing: 4) {
            Rule().opacity(values ? 0 : 1)
            Text(title).font(.system(size: 11)).foregroundStyle(Paint.secondary).padding(.top, 5).opacity(values ? 0 : 1)
            Text(value).font(.system(size: 12.5)).lineLimit(lines, reservesSpace: true).padding(.bottom, 5).opacity(values ? 1 : 0)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
