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
3. Scenes: `overview`, `browse`, `browse-tree`, `empty`, `scanning`, `settings`, `trash-review`, `trash-outcome`, `cleanup-result`.

## Scan and browse

1. Open `Disk Cleaner.app` and choose Choose Folder on the empty screen. The app scans only that folder. It does not follow symbolic links and stops after 100,000 entries, and it tells you the scope and how fresh the scan is.
2. Cancel stops a running scan and keeps your previous saved result. Scan again repeats the current folder.
3. Read **Overview**: whole-disk capacity beside the recorded sizes of the scanned folder. Scan totals are estimates, not space you could free.
4. Open **Browse files**. Click a folder row to go inside. Use the back chevron or a breadcrumb to return; the row you came from stays in view. Browsing uses the saved scan and does not rescan.
5. Search filters the entries; sort by Size, Name or Modified. Select a row to see its path, date and coverage in the inspector.

## Move items to the Trash

1. Tick the checkbox on each item you want. Selecting a row to read it is separate from checking it. The bar shows "N checked for Trash" and their size.
2. Press Review for Trash. The page lists the exact paths. Search, tabs and navigation are locked while it is open.
3. Press Cancel or the back chevron to leave with nothing moved, back at the same folder, position and selection.
4. Press Move to Trash to go ahead. This is the only button that moves anything.
5. Read the outcome per item: **moved**, **not moved** with the reason, or **unknown** with the last known Trash location. Rescan to refresh the numbers.

Moving to the Trash does not free space until you empty it. Finder's Put Back is not promised. The app has not yet been exercised against the real Trash from its own process. If another of your own processes swaps a file at the same instant, the move could act on the swapped file; this is an accepted tradeoff.

## Settings

Open Settings with the gear or Command-comma; it is a page in the same window, and Back or Esc returns. Choose Teal or Violet, whether to remember the last scan, and how many scans to keep: 5, 10 or 30.

## Cleanups

**Cleanups** lists past capacity requests from agents, with targets, measurements and outcomes. A `completed` result means the space was already available. No cleanup category is enabled, so a request for more space than exists answers `insufficient`.

## Your data

The app and the command line share `~/Library/Application Support/DiskCleaner/` for your macOS user.

- `snapshots.json` holds observed paths, names, sizes, dates and errors for the scans you keep.
- `jobs.json` holds capacity requests and their outcomes. It has no size or age limit yet.

The app makes no network requests and stores metadata, not file contents. Paths and file names can still be private. There is no encryption or export.

## If a saved file is damaged

The app reports the error and does not rebuild or reset history. Quit the app and any running `disk-cleanerctl` clients, copy the folder above somewhere safe and note the exact error. Do not delete the files to clear the message. There is no automatic recovery or backup yet.

Next: [automation contract](../reference/automation-contract.md) for agents, or the [documentation index](../README.md).
