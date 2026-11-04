---
audience: maintainer
---

# Appearance

Use this page to understand Disk Cleaner's window atmosphere and the colour rules every screen keeps.

The app has one violet atmosphere and no appearance setting. It uses neutral controls and distinct data colours. Purple or violet is never used for navigation, selection, focus, hover or other control highlights, and the cleanup button is a neutral outlined button. Teal remains one of the approved data hues in charts.

[`DiskCleanerAppearance.swift`](../../Sources/DiskCleanerApp/DiskCleanerAppearance.swift) names the violet atmosphere colours and the shared `Paint` colours. The violet ground and glow colours were adapted from the atmosphere of another Aikongen product's prototype, without adopting its controls or layout. A settings file saved by an earlier build may still contain an `appearance` value; it is ignored and the violet atmosphere is used.

Figures such as 126 GB Documents are example data. The previews are fixture screens, not evidence of a full file browser or cleanup capability.

## First-run pages and Settings

Overview, Browse files and Cleanups before a scan, and Settings, share one layout: a 640 pt column centred in the window and anchored to the top, a title 40 pt below the navigation, a one-line subtitle, then cards. Nothing is vertically centred. While Settings is open the navigation stays visible with no tab selected, and the gear shows as selected; Esc or the gear returns to the previous page. Cleanups links to the Help page "How an agent asks" instead of explaining in the window.

## About panel

About Disk Cleaner opens one small, non-modal panel from the app menu. It is the one deliberate exception to the rule that secondary screens live inside the main window: it is a short reference card, not a settings page, it closes with one click and it keeps no state. The yellow square of the icon lifts away once when the panel opens (it only fades in when Reduce Motion is on). The panel shows the version and build, the first line of the changelog section for that version (hidden when the version has none), and links to release notes, source, problem reports and the licence. The bundled preview app can open it at launch with `--demo --open-about`.
