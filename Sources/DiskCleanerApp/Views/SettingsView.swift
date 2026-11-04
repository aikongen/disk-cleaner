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
                    Picker("Scans to keep", selection: preference(\.retention)) {
                        Text("5").tag(SnapshotRetention.five); Text("10").tag(SnapshotRetention.ten); Text("30").tag(SnapshotRetention.thirty)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 140).disabled(model.retentionLocked)
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
