import SwiftUI
import DiskCleanerCore

/// Settings is a page in the main window (V15 `settings` scene), never a separate window,
/// popup or sheet. Reached with the gear or ⌘,; Back or Esc returns to the page it was opened
/// from, whose scroll and selection stayed mounted underneath. Changes apply in place.
struct SettingsPage: View {
    @ObservedObject var model: CleanerModel
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Button { model.closeSettingsPage() } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(IconStyle()).keyboardShortcut(.cancelAction)
                    .help("Back (Esc)").accessibilityLabel("Back")
                Text("Settings").font(.system(size: 20, weight: .semibold))
            }
            VStack(spacing: 0) {
                SettingRow(title: "Remember last scan", caption: "Keeps the most recent scan available after quitting") {
                    Toggle("Remember last scan", isOn: preference(\.rememberLastScan)).toggleStyle(.switch).labelsHidden().tint(.gray)
                }
                SettingRow(title: "Scan history", caption: model.retentionLocked ? "Available when no scan or Trash review is running" : "Number of saved scans kept") {
                    Picker("Scan history", selection: preference(\.retention)) {
                        Text("5").tag(SnapshotRetention.five); Text("10").tag(SnapshotRetention.ten); Text("30").tag(SnapshotRetention.thirty)
                    }.pickerStyle(.segmented).labelsHidden().frame(width: 130).disabled(model.retentionLocked)
                }
            }
            .padding(.vertical, 4)
            .background { PanelSurface(radius: 9) }
            Text(model.isFixture
                 ? "Example settings, kept only while this preview runs. Nothing is scanned or changed. Go back with the back button or Esc."
                 : "Saved on this Mac for Disk Cleaner only. Fewer kept scans removes the oldest saved scans, never files. Go back with the back button or Esc.")
                .font(.system(size: 12)).foregroundStyle(Paint.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: 536, alignment: .leading)
        .disabled(!model.settingsLoaded)
        .frame(maxWidth: .infinity)
        .padding(.top, 96)
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
