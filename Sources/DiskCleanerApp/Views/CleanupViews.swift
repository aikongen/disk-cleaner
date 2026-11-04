import SwiftUI
import DiskCleanerCore

/// Cleanups. The request header, card outlines and row titles hold still; switching
/// requests fades only the values through. The capacity card is always present, and the
/// right card resizes on the layout spring when its contents differ, so nothing jumps.
struct JobsScreen: View {
    @ObservedObject var model: CleanerModel
    @Environment(\.motionFrame) private var motionFrame
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        if let job = model.job {
            let swap = motionFrame?.request
            VStack(alignment: .leading, spacing: 22) {
                CleanupRequestHeader(model: model, job: job, swap: swap)
                CleanupRequestBody(model: model, job: job, old: swap?.outgoing.job, swap: swap)
            }
            .animation(CleanerMotion.layout(CleanerMotion.navigate, reduceMotion: reduceMotion), value: job.id)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("No cleanup requests yet").font(.system(size: 22, weight: .semibold))
                Text("Requests and their outcomes will appear here. No cleanup rule is enabled.").foregroundStyle(Paint.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 60)
        }
    }
}

struct CleanupRequestBody: View {
    @ObservedObject var model: CleanerModel
    let job: PresentedJob
    /// Preview frames only: the request being left and the fade progress.
    var old: PresentedJob? = nil
    var swap: MotionFrameOverride.Swap? = nil
    private var fade: (out: Double, in: Double)? { swap.map { ($0.out, $0.in) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            CleanupCapacityResult(job: job, old: old, fade: fade)
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Heading(title: "Result")
                    GroupCard {
                        row("Requested by") { $0.requester }
                        row("Requested") { dateText($0.date, time: true) }
                        row("Free-space goal") { bytes($0.goal) }
                        row("Available before") { bytes($0.before) }
                        row("Available after") { bytes($0.after) }
                        row("Measured capacity change") { job in job.before.flatMap { before in job.after.map { "\($0 - before >= 0 ? "+" : "")\(bytes($0 - before))" } } ?? "Not measured" }
                    }
                }.frame(maxWidth: .infinity)
                CleanupMeasurementNote(job: job, demo: model.isFixture, old: old, swap: swap).frame(maxWidth: .infinity)
            }
            HStack(spacing: 16) {
                FadeSwap(key: job.id, outgoing: old.map { Text($0.message).foregroundStyle(Paint.secondary) }, fade: fade) {
                    Text(job.message).foregroundStyle(Paint.secondary)
                }
                Spacer()
                Button("Browse files") { model.show(.browse) }.buttonStyle(NeutralStyle())
            }.frame(minHeight: 34)
        }
    }
    /// The title stays drawn; only the value fades through on a switch.
    private func row(_ title: String, _ value: @escaping (PresentedJob) -> String) -> some View {
        HStack(spacing: 10) {
            Text(title).foregroundStyle(Paint.secondary)
            Spacer(minLength: 12)
            FadeSwap(key: job.id, alignment: .trailing, outgoing: old.map { valueText(value($0)) }, fade: fade) { valueText(value(job)) }
        }
        .font(.system(size: 13)).padding(.horizontal, 16).frame(minHeight: 43)
    }
    private func valueText(_ text: String) -> Text { Text(text).fontWeight(.medium).monospacedDigit() }
}

private struct RequestAnchorKey: PreferenceKey {
    static var defaultValue: [String: Anchor<CGRect>] { [:] }
    static func reduce(value: inout [String: Anchor<CGRect>], nextValue: () -> [String: Anchor<CGRect>]) { value.merge(nextValue()) { $1 } }
}

struct CleanupRequestHeader: View {
    @ObservedObject var model: CleanerModel
    let job: PresentedJob
    let swap: MotionFrameOverride.Swap?
    @Environment(\.motionFrame) private var motionFrame
    @Namespace private var selectedRequest
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ZStack(alignment: .topLeading) {
                if let swap, let old = swap.outgoing.job {
                    title(old).opacity(1 - swap.out)
                    title(job).opacity(swap.in)
                } else {
                    title(job).id(job.id).transition(.fadeThrough)
                }
            }
            .animation(CleanerMotion.fadeIn, value: job.id)
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 2) {
                ForEach(model.jobs) { candidate in
                    Button { model.selectedJob = candidate.id } label: {
                        Text(dateText(candidate.date, time: true)).font(.system(size: 12)).padding(.horizontal, 11).frame(height: 30)
                            .background {
                                if job.id == candidate.id && swap == nil {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.15))
                                        .matchedGeometryEffect(id: "request", in: selectedRequest)
                                }
                            }
                            .anchorPreference(key: RequestAnchorKey.self, value: .bounds) { [candidate.id: $0] }
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            .backgroundPreferenceValue(RequestAnchorKey.self) { anchors in
                // Preview frames only: the pill pinned part-way between two requests.
                if let swap, let pill = motionFrame?.pill, let from = swap.outgoing.job.flatMap({ anchors[$0.id] }), let to = anchors[job.id] {
                    GeometryReader { geometry in
                        let a = geometry[from], b = geometry[to]
                        RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.white.opacity(0.15))
                            .frame(width: a.width + (b.width - a.width) * pill, height: a.height)
                            .position(x: a.midX + (b.midX - a.midX) * pill, y: a.midY)
                    }
                }
            }
            .padding(3).background(.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(.white.opacity(0.08)))
            .animation(CleanerMotion.selection, value: model.selectedJob)
        }.frame(minHeight: 58, alignment: .top)
    }
    private func title(_ job: PresentedJob) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent request · \(dateText(job.date, time: true))").font(.system(size: 22, weight: .semibold))
            HStack(spacing: 8) {
                Circle().fill(job.status == "completed" ? Color.green : job.status == "insufficient" ? Paint.gold : Paint.slate).frame(width: 7, height: 7)
                Text(outcome(job)).font(.system(size: 13)).foregroundStyle(Color(white: 0.82))
            }
        }
    }
    private func outcome(_ job: PresentedJob) -> String {
        switch job.status {
        case "queued": "Request accepted · waiting"
        case "running": "Cleanup in progress"
        case "completed": "Goal reached"
        case "insufficient": model.isFixture ? "Cleanup finished · more space still needed" : "No cleanup rule enabled · more space needed"
        case "interrupted": "Cleanup interrupted · result may be incomplete"
        default: "Cleanup failed"
        }
    }
}

/// Always present: without a measured result it keeps its height and says so. The card
/// and the bar's track stay drawn; the figures fade through on a switch and the bar
/// itself changes directly (measurements never interpolate).
struct CleanupCapacityResult: View {
    let job: PresentedJob
    var old: PresentedJob? = nil
    var fade: (out: Double, in: Double)? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            FadeSwap(key: job.id, alignment: .bottomLeading, outgoing: old.map(figures), fade: fade) { figures(job) }
                .frame(height: 36, alignment: .bottomLeading)
            GeometryReader { proxy in
                let full = proxy.size.width
                RoundedRectangle(cornerRadius: 5).fill(.white.opacity(0.11))
                    .overlay(alignment: .leading) {
                        if let after = job.after { RoundedRectangle(cornerRadius: 5).fill(Paint.teal).frame(width: full * min(1, max(0, Double(after) / Double(max(job.goal, 1))))) }
                    }
                    .overlay(alignment: .leading) {
                        if let before = job.before { Rectangle().fill(.white.opacity(0.86)).frame(width: 2).offset(x: max(0, full * min(1, max(0, Double(before) / Double(max(job.goal, 1)))) - 1)) }
                    }
            }.frame(height: 10).transaction { $0.animation = nil }
            FadeSwap(key: job.id, outgoing: old.map(legend), fade: fade) { legend(job) }
        }.padding(17).background { PanelSurface() }
    }
    private func figures(_ job: PresentedJob) -> some View {
        let after = job.after
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(after.map { bytes($0) } ?? "Not measured yet").font(.system(size: after == nil ? 20 : 30, weight: .semibold)).monospacedDigit()
                .foregroundStyle(after == nil ? Paint.secondary : Color(white: 0.96))
            Text(after == nil ? "available space after this request" : "available after\(job.before.map { " (was \(bytes($0)))" } ?? "")").foregroundStyle(Paint.secondary)
            Spacer()
            if let after { Text(after >= job.goal ? "Goal reached" : "\(bytes(job.goal - after)) short of goal").foregroundStyle(Paint.secondary) }
        }
    }
    private func legend(_ job: PresentedJob) -> some View {
        HStack { Text("0 GB"); Spacer(); Text("Marker: available before · Goal \(bytes(job.goal))") }.font(.system(size: 11)).foregroundStyle(Paint.secondary)
    }
}
/// The card outline stays; when two requests show different contents, those contents
/// fade through and the card resizes on the layout spring.
struct CleanupMeasurementNote: View {
    let job: PresentedJob
    let demo: Bool
    var old: PresentedJob? = nil
    var swap: MotionFrameOverride.Swap? = nil
    var body: some View {
        let fade = swap.map { (out: $0.out, in: $0.in) }
        VStack(alignment: .leading, spacing: 6) {
            FadeSwap(key: heading(job), outgoing: old.map { Heading(title: heading($0)) }, fade: old.map { heading($0) } != heading(job) ? fade : nil) { Heading(title: heading(job)) }
            GroupCard {
                ArrivingSized(current: job.id, pinned: swap?.height) {
                    if let swap, let old {
                        contents(old).opacity(1 - swap.out).layoutValue(key: MotionStateKey.self, value: old.id)
                        contents(job).opacity(swap.in).layoutValue(key: MotionStateKey.self, value: job.id)
                    } else {
                        contents(job)
                            .transaction { $0.animation = nil }
                            .layoutValue(key: MotionStateKey.self, value: job.id)
                            .id(job.id)
                            .transition(.fadeThrough)
                    }
                }
            }
        }
    }
    private func heading(_ job: PresentedJob) -> String { job.demoEstimate ? "Package cache · scan estimates before cleanup" : "Measured result" }
    @ViewBuilder private func contents(_ job: PresentedJob) -> some View {
        VStack(spacing: 0) {
            if job.demoEstimate {
                ValueRow(title: "Total cache", value: "15 GB")
                ValueRow(title: "Estimated unused", value: "6.2 GB", marker: Paint.teal)
                ValueRow(title: "Estimated used and retained", value: "8.8 GB", marker: Color.white.opacity(0.25))
                Text("The 4.1 GB is the measured change in available space, not the amount of cache files deleted; deleted file bytes were not measured. Capacity gain was below the estimate; cause was not measured.")
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.82)).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(demo ? "Available space rose from 12.1 GB to 18.0 GB, a measured change of +5.9 GB." : job.message)
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.82)).padding(16).frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
            }
        }
    }
}
