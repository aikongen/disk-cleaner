# Contributing

Disk Cleaner is a macOS 14+ Swift package: `DiskCleanerCore`, the `DiskCleanerApp` executable and the `disk-cleanerctl` command line tool. Read [AGENTS.md](AGENTS.md) and the [maintainer guide](docs/maintainer-guide.md) first.

## Build and test

```sh
swift build
swift test
swift build -c release
```

## Tests use fixtures only

Tests and previews use fixture data and temporary directories. Never scan a personal folder, open the real Application Support data or move real files to the Trash in a test. `DISK_CLEANER_RUN_REAL_TRASH_SMOKE` stays unset in CI and in normal runs.

## Interface rules

Keep Overview, Browse files and Cleanups. Use dark, layered native materials and distinct data hues. No purple or violet controls or highlights. Every disclosure row is a whole-row target at least 28 pt tall with a pointing cursor. Motion that explains navigation, selection or disclosure must survive feature work and handle reversal.

## Docs

Pages live in [docs](docs/README.md) under Diátaxis folders (tutorials, how-to, explanation, reference). Each page has `audience:` front matter and one index line in `docs/README.md`.

## Changelog and pull requests

Add an entry under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md) for every user-visible change. Open a pull request with the [template](.github/PULL_REQUEST_TEMPLATE.md); include screenshots or frames for UI changes.

By contributing you agree that your contributions are licensed under the MIT License.
