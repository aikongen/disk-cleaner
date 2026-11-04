---
audience: consumer
---

# Open Disk Cleaner, scan a folder and review what to move

Use this page to open the app, see what fills a folder, and, if you choose, move items to the Trash after a review. Disk Cleaner never deletes permanently and never acts on its own.

## Before you start

- macOS 14 or later on an Apple silicon Mac, with the release zip downloaded and unzipped as described under Get it in the [README](../README.md). It holds both apps.
- The apps are ad-hoc signed development builds, not notarized. macOS may ask you to confirm the first launch.
- The **preview** (`Disk Cleaner Preview.app`, or the app started with `--demo`) shows example data and can never move a file. The **normal app** (`Disk Cleaner.app`) scans a folder you choose and can move checked items to the Trash.

## Try the preview first

1. Open `Disk Cleaner Preview.app`. Its footer says it shows example data with no disk actions. Figures such as "126 GB Documents" are examples.
2. To open one screen directly, quit it and start it with a scene: `open -n "Disk Cleaner Preview.app" --args --scene trash-review`. Setting `DISK_CLEANER_SCENE` does the same from a shell.
3. Scenes: `overview`, `browse`, `browse-tree`, `empty`, `browse-empty`, `cleanups-empty`, `scanning`, `settings`, `trash-review`, `trash-outcome`, `cleanup-result`.

## Scan and browse

1. Open `Disk Cleaner.app` and choose **Choose folder…** on Overview, which also shows the free space on your startup disk, or on the empty Browse files page. The app scans only that folder. It does not follow symbolic links and stops after 100,000 entries, and it tells you the scope and how fresh the scan is.
2. Cancel stops a running scan and keeps your previous saved result. Scan again repeats the current folder.
3. Read **Overview**: whole-disk capacity beside the recorded sizes of the scanned folder. Scan totals are estimates, not space you could free.
4. Open **Browse files**. Click a folder row to go inside. Use the back chevron or a breadcrumb to return; the row you came from stays in view. Browsing uses the saved scan and does not rescan.
5. Search filters the entries; sort by Size, Name or Modified. Select a row to see its path, date and coverage in the inspector.

## Where to go next

- [Find items and move them to the Trash](../how-to/browse-and-trash.md) for the review and the outcome per item.
- [Change settings and read Cleanups](../how-to/settings.md).
- [Limits and your data](../explanation/limits.md) for what is stored and what is not promised.
- [Agents and the command line](../reference/automation-contract.md), or the [documentation index](../README.md).
