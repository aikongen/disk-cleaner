import SwiftUI
import DiskCleanerCore

// Official previews: one per fixture scene. All use example data only.
struct ScenePreview: View {
    let scene: FixtureScene
    var body: some View {
        CleanerWindow(model: CleanerModel(isFixture: true, scene: scene))
            .preferredColorScheme(.dark).tint(.gray).frame(width: 1200, height: 840)
    }
}
// Each scene preview lives in its own DiskCleanerScene*Preview.swift file: the official
// RenderPreview tool rendered the wrong index in files with several previews.
