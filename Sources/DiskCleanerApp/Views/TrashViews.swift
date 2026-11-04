import SwiftUI
import DiskCleanerCore

/// Shown in the list column's place. The path list scrolls inside itself when it is longer
/// than the visible area, because the page below is held still while the review is open.
struct TrashReviewScreen: View {
    @ObservedObject var model: CleanerModel
    var availableHeight: CGFloat = 10_000
    /// Measured height of everything except the path list, so the list gives way and the
    /// buttons stay in view while the page scroll is held.
    @State private var above: CGFloat = 90
    @State private var below: CGFloat = 170
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { model.cancelReview() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconStyle()).disabled(model.trashBusy).help("Back to the selection")
                    .accessibilityLabel("Back to selection")
                Text("Review before moving to Trash").font(.system(size: 20, weight: .semibold))
            }
            if let review = model.review {
                Text("\(review.items.count) selected · \(bytes(review.totalBytes)). These exact paths are checked for Trash:")
                    .foregroundStyle(Color(white: 0.86))
            }
            }.measuredHeight($above)
            if let review = model.review {
                GroupCard { CappedList(cap: max(120, availableHeight - above - below - 14 * 2)) { VStack(spacing: 0) {
                    ForEach(review.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                FullPathText(path: item.path)
                                Text(item.isDirectory ? "Folder and everything in it" : "File").font(.system(size: 11)).foregroundStyle(Paint.secondary)
                            }
                            Spacer()
                            Text(bytes(item.bytes)).monospacedDigit()
                        }.padding(.horizontal, 14).padding(.vertical, 9)
                        if item.id != review.items.last?.id { Rule() }
                    }
                } } }
                VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("**Moving to Trash does not immediately free space.** Available space is not re-measured by this step.")
                    Text("Nothing else is selected or removed automatically; no cleanup follows.")
                    Text("Scan root: \(review.root)").font(.system(size: 11)).foregroundStyle(Paint.secondary).textSelection(.enabled)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background { PanelSurface(radius: 9) }
                HStack(spacing: 12) {
                    Button("Cancel") { model.cancelReview() }.buttonStyle(GhostStyle()).disabled(model.trashBusy)
                        .keyboardShortcut(.cancelAction)
                    Button(role: .destructive) { model.confirmTrash() } label: { Text("Move to Trash") }
                        .buttonStyle(GhostStyle(tint: model.canConfirmTrash ? Paint.destructive : .white))
                        .disabled(!model.canConfirmTrash)
                    if model.trashBusy { ProgressView().controlSize(.small).tint(.gray); Text("Moving selected items…").foregroundStyle(Paint.secondary) }
                    else if let held = model.confirmHeldReason { Text(held).font(.system(size: 12)).foregroundStyle(Paint.warning) }
                    else if !model.isFixture { Text("Moves only these paths. Recover items from Trash by hand; there is no Undo.").font(.system(size: 12)).foregroundStyle(Paint.secondary) }
                    else if model.isFixture { Text("Example data · items are only marked; nothing on disk is moved").font(.system(size: 12)).foregroundStyle(Paint.secondary) }
                }
                }.measuredHeight($below)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TrashOutcomeScreen: View {
    @ObservedObject var model: CleanerModel
    var availableHeight: CGFloat = 10_000
    /// Measured like the review, so Back to selection and Browse files stay in view.
    @State private var above: CGFloat = 70
    @State private var below: CGFloat = 260
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("Trash outcome").font(.system(size: 20, weight: .semibold))
            }
            if let outcome = model.outcome {
                let unknown = outcome.items.filter { $0.status == .unknown }.count
                let notMoved = outcome.items.count - outcome.movedCount - unknown
                HStack(spacing: 8) {
                    Circle().fill(notMoved == 0 && unknown == 0 ? Paint.moved : Paint.warning).frame(width: 7, height: 7)
                    Text("\(outcome.movedCount) of \(outcome.items.count) moved to Trash\(notMoved > 0 ? " · \(notMoved) not moved" : "")\(unknown > 0 ? " · \(unknown) outcome unknown" : "")")
                }
            }
            }.measuredHeight($above)
            if let outcome = model.outcome {
                GroupCard { CappedList(cap: max(120, availableHeight - above - below - 14 * 2)) { VStack(spacing: 0) {
                    ForEach(outcome.items) { item in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                FullPathText(path: item.path)
                                if item.status != .moved || model.isFixture {
                                    Text(item.message).font(.system(size: 11)).foregroundStyle(item.status == .moved ? Paint.secondary : Paint.warning)
                                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                }
                                if let trashPath = item.trashPath {
                                    Text("Last known location in Trash: \(trashPath). It may no longer be there.")
                                        .font(.system(size: 11)).foregroundStyle(Paint.secondary)
                                        .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                                }
                            }
                            Spacer()
                            Text(item.status.title).foregroundStyle(item.status == .moved ? Paint.moved : Paint.warning)
                        }.padding(.horizontal, 14).padding(.vertical, 9)
                        if item.id != outcome.items.last?.id { Rule() }
                    }
                } } }
                VStack(alignment: .leading, spacing: 14) {
                if outcome.requiresRescan {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Scan again before another file action").fontWeight(.medium)
                            Text("Sizes and capacity on screen still describe the earlier scan.").font(.system(size: 12)).foregroundStyle(Paint.secondary)
                            if let reason = model.scanControlsDisabledReason, model.isFixture { Text(reason).font(.system(size: 11)).foregroundStyle(Paint.secondary) }
                        }
                        Spacer()
                        Button("Scan Again") { model.closeOutcome(); model.rescan() }.buttonStyle(NeutralStyle(compact: true))
                            .disabled(model.isFixture || model.scanning)
                    }.padding(14).background { PanelSurface(radius: 9) }
                }
                if let error = outcome.persistenceError {
                    Text("The saved scan could not be marked out of date: \(error)").foregroundStyle(Paint.warning).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("**Available space has not been measured after this step.** Moving to Trash does not immediately free space.")
                    Text("No automatic cleanup was started. Items moved by this app have no Finder Put Back; restore them from Trash by hand.")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(maxWidth: .infinity, alignment: .leading).background { PanelSurface(radius: 9) }
                HStack(spacing: 12) {
                    Button("Back to selection") { model.closeOutcome() }.buttonStyle(GhostStyle())
                    Button("Browse files") { model.closeOutcome(); if let root = model.root?.path { model.navigate(root) } }.buttonStyle(GhostStyle())
                }
                }.measuredHeight($below)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension View {
    func measuredHeight(_ height: Binding<CGFloat>) -> some View {
        onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height.wrappedValue = $0 }
    }
}

/// Content height up to `cap`; beyond that it scrolls inside itself. The height comes from
/// the content's own layout in the same pass (no measuring state), so the first frame is
/// already at its final height.
struct CappedList<Content: View>: View {
    let cap: CGFloat
    @ViewBuilder var content: Content
    var body: some View {
        CappedHeight(cap: cap) {
            content.hidden()
            ScrollView { content }.scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct CappedHeight: Layout {
    let cap: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let measure = subviews.first else { return .zero }
        let size = measure.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil))
        return CGSize(width: proposal.width ?? size.width, height: min(size.height, cap))
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 2 else { return }
        subviews[0].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: nil))
        subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
