# Changelog

This file records user-visible changes. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## Unreleased

- Releases include a drag-to-install `.dmg` beside the zip.
- README rewritten for people who download the app; build instructions moved to the maintainer guide.
- Removed the Teal appearance option; the app has one violet atmosphere.

## 0.1.0 - 2026-11-04

### Added

- Product icon: one yellow piece lifted clear of a silver mass; the mass is what stays.
- First public source. Inspect a folder you choose and keep the scan.
- Browse the saved scan without rescanning, with breadcrumbs, search and sort.
- Review exact paths and move only the items you checked to the Trash, with an outcome for each item.
- A Settings page with a Teal or Violet window atmosphere, remembering the last scan, and keeping the last 5, 10 or 30 scans.
- A same-user command line tool, `disk-cleanerctl`, for an agent to request an amount of available capacity. The agent supplies no paths, commands or rules.
- A fixture preview app that shows every screen with example data. Open one screen with `--scene`.
- MIT license.

### Known limits

- The apps are ad-hoc signed and not notarized.
- Nothing is freed automatically, and no cleanup category is enabled.
- Moving an item to the Trash does not promise that Finder's Put Back will work.
