---
audience: consumer
---

# Disk Cleaner docs

For the person using Disk Cleaner on their own Mac, for an agent calling its command line tool, and for maintainers changing the source. Each page names its audience in front matter and opens with the task it serves. Nothing is described as existing unless it exists today; unfinished work is labelled "planned" or "in progress". Folders follow Diátaxis: tutorials teach by doing, how-to guides solve one task, explanations say why, references list facts.

## Tutorials

- [Open Disk Cleaner, scan a folder and review what to move](tutorials/first-scan.md) opens the app, browses a scan and walks the Trash review.

## How-to guides

- [Find items and move them to the Trash](how-to/browse-and-trash.md) browses a saved scan, checks items and moves them after a review.
- [Change settings and read Cleanups](how-to/settings.md) sets how many scans are kept and lists agent requests.
- [Publish a release](how-to/release.md) tags a version and checks the download checksum (maintainer).

## Explanation

- [What Disk Cleaner does](explanation/what-it-does.md) says what it shows, what you can do and what it never does.
- [Limits and your data](explanation/limits.md) says what is stored and what is not promised.
- [Architecture and quality path](explanation/architecture-and-readiness.md) says how the parts fit and what must improve next (maintainer).
- [Appearance](explanation/appearance.md) covers the window atmosphere and the colour rules (maintainer).

## Reference

- [Keyboard shortcuts](reference/keyboard-shortcuts.md) lists the keys the app defines.
- [Automation contract](reference/automation-contract.md) lists the `disk-cleanerctl` commands, JSON fields and statuses.

## Maintainer

- [Maintainer guide](maintainer-guide.md) covers getting the source, build, test, the example-data preview, fixture isolation and evidence conventions.
