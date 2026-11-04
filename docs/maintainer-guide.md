---
audience: maintainer
---

# Maintain Disk Cleaner

Use this page when you change Disk Cleaner's source: how to build and test it, how to keep tests away from personal data, and what counts as evidence for a claim. Working rules for people and agents are in [AGENTS.md](../AGENTS.md).

## Get the source and build

```sh
git clone https://github.com/aikongen/disk-cleaner.git
cd disk-cleaner
```

Building needs macOS 14 or later and Xcode 16 or later (Swift 6). It has been built and tested only on Apple silicon. Run `swift build -c release`, `swift test` and `scripts/build-and-package.sh` as listed below. `swift test` uses fixtures in temporary folders only. `scripts/build-and-package.sh` writes two apps to `artifacts/`: `Disk Cleaner.app`, with `disk-cleanerctl` inside, and `Disk Cleaner Preview.app`, example data only. Both are ad-hoc signed, not notarized, so macOS may ask for confirmation on first launch. A download with the GitHub CLI avoids quarantine: `gh release download vX.Y.Z -R aikongen/disk-cleaner -p 'DiskCleaner-*'` (see [Publish a release](how-to/release.md)).

## Preview with example data

The preview shows every screen with example data and cannot touch your disk. Open one screen directly with `--scene`:

```sh
swift run DiskCleanerApp --demo --scene browse
open -n "artifacts/Disk Cleaner Preview.app" --args --scene trash-review
```

Scenes: `overview`, `browse`, `browse-tree`, `empty`, `scanning`, `settings`, `trash-review`, `trash-outcome`, `cleanup-result`.

## Run the command line tool

```sh
cli="/path/to/Disk Cleaner.app/Contents/MacOS/disk-cleanerctl"
"$cli" request 24000000000 'my-unique-request-key'   # ask for 24 GB available, get a job id
"$cli" wait '<job-id>'                               # completed, insufficient, failed or interrupted
```

Every command, field and status is in the [automation contract](reference/automation-contract.md).

## Build and test

The Swift package in `Package.swift` is the module definition: `DiskCleanerCore`, the `DiskCleanerApp` executable, the `disk-cleanerctl` executable and the `DiskCleanerCoreTests` test target, with macOS 14 as the minimum.

```sh
swift build                    # debug build of every product
swift build -c release         # release build
swift test                     # fixture tests in temporary folders
scripts/build-and-package.sh   # tests, release build, two ad-hoc signed bundles in artifacts/
```

`scripts/make-icon-assets.sh <source-1024.png>` regenerates every icon-derived asset (icns, Xcode AppIcon catalog, `assets/icon.png`, README hero) from one 1024 px PNG.

The packaging script refuses an output folder outside the repository, replaces only its two named bundles, and writes source and executable SHA-256 manifests plus `BUILD-INFO.txt` beside them. The bundles are development artifacts, not Developer ID signed or notarized distributions.

`xcode/DiskCleanerHost/DiskCleanerHost.xcodeproj` builds the same `Sources/` and `Tests/` through Xcode, so Apple's Xcode build, test and preview tools can work on them. Its file references are relative to the repository root. The `DiskCleaner` scheme builds the Core framework, the normal app, the CLI and the tests; `DiskCleanerFunctionalPreview` builds the example-data app. The Xcode app target does not embed `disk-cleanerctl`; the packaging script does. When you add or remove a source file, add or remove it in the Xcode project too.

## Boundaries

- `DiskCleanerCore`: Codable models, the metadata inventory scanner, comparable observations, JSON and lock persistence, capacity-check jobs and the reviewed manual Trash move. No dependency on AppKit or SwiftUI and no cleanup provider registry.
- `DiskCleanerApp`: the SwiftUI and AppKit shell, presentation state and model-to-view mapping. It calls Core for scans, jobs and reviewed Trash moves.
- `DiskCleanerCLI`: validates arguments, persists and retrieves Core jobs and starts its own worker. It does not accept filesystem paths or commands.
- `DiskCleanerCoreTests`: isolated Core, scanner, app-model and same-build DEBUG CLI fixtures. No test authorizes scanning user folders or enabling a cleanup category.

Grow these modules where a concrete limit appears (unbounded JSON storage, compatibility, real cleanup policy). Do not add services, frameworks or product responsibilities just to split files.

## Keep tests and previews on fixtures

- Tests use temporary directories. The opt-in real-Trash smoke test runs only with `DISK_CLEANER_RUN_REAL_TRASH_SMOKE=1`; leave it unset in routine runs and CI.
- The app's fixture mode (`--demo`, `DISK_CLEANER_DEMO=1` or the preview bundle's `DiskCleanerDemoMode` key) returns before the polling loop, uses example data and makes no scan, Trash or Finder operation. Open single screens with `--scene <name>` or `DISK_CLEANER_SCENE`.
- DEBUG CLI fixtures need both `DISK_CLEANER_FIXTURE_MODE=1` and an absolute `DISK_CLEANER_FIXTURE_DIR` containing `.disk-cleaner-fixture`. Release builds ignore these variables and use the normal `~/Library/Application Support/DiskCleaner/`, so never run a release CLI with fixture variables and assume isolation. See the [automation contract](reference/automation-contract.md).
- Do not run the normal app or CLI against your own Application Support or personal folders as a verification shortcut.

## Evidence conventions

- Report the actual test output (counts of passed, failed and skipped tests), not a number printed by a script.
- A green fixture suite does not establish arbitrary filesystem scale, true disk exhaustion, power-loss durability, release packaging, real cleanup safety or behaviour on every macOS version. Match new claims to evidence for that claim.
- A rendered still is not motion evidence, and a harnessed property change is not physical input.
- For Apple-platform work, use Apple's agentic Xcode tools (workspace connection, build, tests, previews, documentation search) where they apply, and record which ones ran. A shell build alone does not show that integration.
- Keep built apps, screenshots and evidence files out of the repository; `.local/` is ignored for that purpose.

## Documentation

Update the [tutorial](tutorials/first-scan.md) and the [automation contract](reference/automation-contract.md) when behaviour changes, and label unfinished work "planned". Each page carries `audience: consumer` or `audience: maintainer` front matter and is listed in the [documentation index](README.md).

Private planning records, delivery notes and session evidence are kept outside the repository.
