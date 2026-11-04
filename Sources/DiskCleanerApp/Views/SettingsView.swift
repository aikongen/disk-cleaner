import SwiftUI
import DiskCleanerCore

/// Settings is a page in the main window (V15 `settings` scene), never a separate window,
/// popup or sheet. Reached with the gear or ⌘,; Back or Esc returns to the page it was opened
/// from, whose scroll and selection stayed mounted underneath. Changes apply in place.
struct SettingsPage: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        FirstRunPage(title: "Settings", subtitle: "Esc or the gear takes you back", subtitleSmall: true) {
            VStack(spacing: 0) {
                SettingRow(title: "Open my last scan when the app starts") {
                    Toggle("Open my last scan when the app starts", isOn: preference(\.rememberLastScan)).toggleStyle(.switch).labelsHidden().tint(.gray)
                }
                Rule().padding(.horizontal, 16)
                SettingRow(title: "Scans to keep") {
                    SegmentedChoice(options: SnapshotRetention.allCases.map { ($0, "\($0.rawValue)") }, selection: preference(\.retention))
                        .frame(width: 140).disabled(model.retentionLocked)
                        .help(model.retentionLocked ? "Available when no scan or Trash review is running" : "")
                }
            }
            .padding(.vertical, 2)
            .background { PanelSurface(radius: 10) }
            Text("Older scans leave the history list. Your files are not touched.")
                .font(.system(size: 12)).foregroundStyle(Paint.secondary).padding(.top, -6)
        }
        // Esc goes back to the exact previous page; the gear in the navigation does the same.
        .background { Button("") { model.closeSettingsPage() }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true) }
        .disabled(!model.settingsLoaded)
    }
    private func preference<Value>(_ keyPath: WritableKeyPath<UserPreferences, Value>) -> Binding<Value> {
        Binding(get: { model.preferences[keyPath: keyPath] }, set: { model.setPreference(keyPath, to: $0) })
    }
}

struct SettingRow<Control: View>: View {
    let title: String
    var caption: String? = nil
    @ViewBuilder var control: Control
    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                if let caption { Text(caption).font(.system(size: 11)).foregroundStyle(Paint.secondary) }
            }
            Spacer()
            control
        }.padding(.horizontal, 16).frame(minHeight: 44)
    }
}

/// Small segmented control whose highlight slides on the selection spring, like the nav and
/// Browse rows. Each whole segment is the hit target (30 pt tall) with a pointing cursor.
struct SegmentedChoice<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @Namespace private var highlight

    var body: some View {
        HStack(spacing: 0) {
            ForEach(options.indices, id: \.self) { i in
                let value = options[i].0
                Button { selection = value } label: {
                    Text(options[i].1).font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(selection == value ? 0.96 : 0.76))
                        .frame(maxWidth: .infinity).frame(height: 30)
                        .contentShape(Rectangle())
                        .background {
                            if selection == value {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(.white.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.white.opacity(0.16)))
                                    .matchedGeometryEffect(id: "segment", in: highlight)
                            }
                        }
                }.buttonStyle(.plain).pointingCursor()
            }
        }
        .padding(2).background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(.white.opacity(0.08)))
        .animation(CleanerMotion.layout(CleanerMotion.selection, reduceMotion: reduceMotion), value: selection)
        .opacity(enabled ? 1 : 0.5)
    }
}
