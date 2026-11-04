# Disk Cleaner

Disk Cleaner shows what fills your Mac's disk, so you can understand it and move only what you choose to the Trash, and lets an agent ask for a target amount of free space without being able to delete anything.

**Honest limit: it never frees space on its own. No automatic cleanup is enabled, nothing is deleted permanently, and an agent's capacity request can truthfully answer "insufficient".**

## Why Disk Cleaner

- **See what fills your disk.** Scan a folder you choose and read capacity and sizes side by side, with the scope and age of the scan stated.
- **Browse without rescanning.** The saved scan stays on your Mac. Click through folders, use breadcrumbs and back, search, and sort by Size, Name or Modified.
- **Honest numbers.** Estimates, file sizes and measured free-space changes are shown as different things, and unknown stays unknown.
- **Agents can ask, not act.** An agent requests a target amount of available space through a command line tool and gets a job id and status. It cannot pass paths, commands or rules.
- **Nothing moves without you.** You check exact items, review their paths, then confirm. Items go to the Trash, never straight to deletion.

Disk Cleaner is a personal, local macOS app. Data stays on your Mac.

## Install

There is no installer or public release yet. You build Disk Cleaner from source on macOS 14 or later with Xcode 16 or later (Swift 6 toolchain). It has been built and tested only on Apple silicon with Xcode 27.

```sh
git clone https://github.com/aikongen/disk-cleaner.git
cd disk-cleaner
swift build -c release
swift test
```

`swift test` runs the fixture tests in temporary folders. One opt-in test that moves a generated file into your real Trash stays skipped unless you set `DISK_CLEANER_RUN_REAL_TRASH_SMOKE=1`.

To get double-clickable apps, run `scripts/build-and-package.sh`. It runs the tests, builds the release executables and writes two ad-hoc signed bundles to `artifacts/`: `Disk Cleaner.app` (normal, with `disk-cleanerctl` inside) and `Disk Cleaner Preview.app` (example data only). They are not notarized, so macOS may ask you to confirm the first launch.

To work in Xcode, open `xcode/DiskCleanerHost/DiskCleanerHost.xcodeproj`. Its `DiskCleaner` scheme builds the app, the command line tool and the tests from the same `Sources/` and `Tests/` folders; the `DiskCleanerFunctionalPreview` scheme builds the example-data preview.

### Try the example data first

The preview never reads or moves your files. Start the built app in fixture mode with `--demo` or `DISK_CLEANER_DEMO=1`, and open one screen directly with `--scene <name>` or `DISK_CLEANER_SCENE`:

```sh
swift run DiskCleanerApp --demo --scene browse
DISK_CLEANER_DEMO=1 DISK_CLEANER_SCENE=trash-review swift run DiskCleanerApp
open -n "artifacts/Disk Cleaner Preview.app" --args --scene settings
```

Scenes: `overview`, `browse`, `browse-tree`, `empty`, `scanning`, `settings`, `trash-review`, `trash-outcome`, `cleanup-result`. Figures such as "126 GB Documents" are example data. The tutorial [Open Disk Cleaner, scan a folder and review what to move](docs/tutorials/first-scan.md) walks through both modes.

## Use

1. Open the normal app (without `--demo`) and choose a folder to scan. You can cancel a scan and keep the previous result.
2. Read **Overview** for disk capacity beside the folder's recorded sizes.
3. Open **Browse files**. Click a folder row to go inside, use the breadcrumbs or back to return, and search or sort.
4. Select a row for details. Tick the checkbox to check items for Trash; the bar shows how many and how large.
5. Press Review for Trash to see the exact paths. Nothing moves until you press Move to Trash. Cancel returns you to the same place.
6. Read the outcome per item: moved, not moved with the reason, or unknown with the last known Trash location. Rescan to refresh.

**Cleanups** lists past agent capacity requests and their outcomes. Settings (gear or Command-comma) lets you choose Teal or Violet, remember the last scan, and keep 5, 10 or 30 scans.

Limits to know: Move to Trash does not free space by itself until the Trash is emptied; Finder's Put Back is not promised; the app has not yet been run against the real Trash from its own process; and if another process of yours swaps a file in the same instant, the move can act on the swapped file (accepted tradeoff).

## Automation

`disk-cleanerctl` is a same-user command line tool inside the normal app. `request` takes a target of available bytes and a key, returns a job id, and `status` or `wait` report the result. It is asynchronous and polling-based. A finished job can say `insufficient`. See the [automation contract](docs/reference/automation-contract.md).

## Documentation

- [Documentation index](docs/README.md)
- [Open Disk Cleaner, scan a folder and review what to move](docs/tutorials/first-scan.md)
- [Automation contract](docs/reference/automation-contract.md)

## Contribute / Maintain

Build, test, fixture isolation and evidence conventions are in the [maintainer guide](docs/maintainer-guide.md). Working rules for contributors and agents are in [AGENTS.md](AGENTS.md).
