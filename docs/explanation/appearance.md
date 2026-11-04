---
audience: maintainer
---

# Appearance

Use this page to understand Disk Cleaner's two window atmospheres and the colour rules every screen keeps.

The default atmosphere is green, shown in Settings as **Teal**; it is the approved look. The violet atmosphere, shown as **Violet**, began as a comparison and is a choice in Settings, not the default. Both atmospheres use neutral controls and distinct data colours. Purple or violet is never used for navigation, selection, focus, hover or other control highlights, and the cleanup button is a neutral outlined button.

[`DiskCleanerAppearance.swift`](../../Sources/DiskCleanerApp/DiskCleanerAppearance.swift) names the green and violet atmosphere colours and the shared `Paint` colours. The saved preference is `AppearancePreference` (`green` or `purple`) in [`Preferences.swift`](../../Sources/DiskCleanerCore/Preferences.swift). The violet ground and glow colours were adapted from the atmosphere of another Aikongen product's prototype, without adopting its controls or layout.

To compare the two, open the preview's Settings scene (`--demo --scene settings`) and switch between Teal and Violet. Figures such as 126 GB Documents are example data. The previews are fixture screens, not evidence of a full file browser or cleanup capability.
