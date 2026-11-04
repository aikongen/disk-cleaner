---
audience: consumer
---

# Limits and your data

Use this page to learn what Disk Cleaner stores, what it does not promise and what to do if a saved file is damaged.

## What moving to the Trash does not promise

Moving to the Trash does not free space until you empty it. Finder's Put Back is not promised. The app has not yet been exercised against the real Trash from its own process. If another of your own processes swaps a file at the same instant, the move could act on the swapped file; this is an accepted tradeoff.

## Your data

The app and the command line share `~/Library/Application Support/DiskCleaner/` for your macOS user.

- `snapshots.json` holds observed paths, names, sizes, dates and errors for the scans you keep.
- `jobs.json` holds capacity requests and their outcomes. It has no size or age limit yet.

The app makes no network requests and stores metadata, not file contents. Paths and file names can still be private. There is no encryption or export.

## If a saved file is damaged

The app reports the error and does not rebuild or reset history. Quit the app and any running `disk-cleanerctl` clients, copy the folder above somewhere safe and note the exact error. Do not delete the files to clear the message. There is no automatic recovery or backup yet.

Next: [automation contract](../reference/automation-contract.md) for agents, or the [documentation index](../README.md).
