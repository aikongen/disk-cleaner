# Disk Cleaner project instructions

These rules apply to every person and AI agent changing this repository. Read [README.md](README.md) and the [maintainer guide](docs/maintainer-guide.md) before choosing work, and distinguish accepted scope, implemented code, fixture demonstrations and unknown behaviour.

## Source and workflow

1. Work from the latest `origin/main` (fetch first) in your own branch or worktree, never in a checkout someone else is using.
2. `Package.swift` defines the modules. `xcode/DiskCleanerHost/DiskCleanerHost.xcodeproj` builds the same `Sources/` and `Tests/`; keep its file list in step when you add or remove a source file.
3. Built apps, screenshots, evidence and private notes go under `.local/`, which is ignored. Never commit them.

## Apple workflow and verification

At the start of Apple-platform work, find the applicable official Apple agentic Xcode tools, confirm the workspace they are connected to, and use them for documentation, builds, diagnostics, tests and previews. Record which tools ran and the decisive result. A shell build or an installed agent toolkit alone does not prove that integration. If the applicable tools are unavailable, report that as a blocker rather than silently falling back. Command-line `swift build` and `swift test` remain valid complements.

Report the actual test output. No new test suite is required for a reversible wording or appearance-only change. Delivering a UI change means a built, signed app in which the changed state can be reached; compilation alone is not delivery.

## Product authority and fixtures

- Human operators and AI clients consume this product's interfaces. Agents request a target available capacity; they do not provide deletion paths, shell commands or cleanup rules.
- No cleanup category or provider is enabled or approved. Never expose `pnpm store prune`, raw cache deletion or age-based removal from this implementation. An `insufficient` result is honest, not permission to broaden scope.
- Moving items to the Trash happens only for items the person checked, after the review page and an explicit Move to Trash. Nothing is deleted permanently.
- Use fixture-only previews and bounded temporary-directory tests. Do not launch the normal app or CLI against real Application Support or scan personal folders as a verification shortcut. Leave `DISK_CLEANER_RUN_REAL_TRASH_SMOKE` unset unless that test is the point of the task. A release CLI ignores fixture variables; see the [automation contract](docs/reference/automation-contract.md).
- Preserve the Core, App and CLI boundaries, stored history and source provenance. The product has no MCP server, daemon, event bus or runtime AI; their absence is not authority to add them.
- External public code is inspiration only. Inspect pinned source, tests and licence before proposing reuse; inspection does not imply a fork, copied core or new dependency.

## UI rules

Keep Overview, Browse files and Cleanups; dark layered native materials; distinct data hues; no purple or violet for controls or highlights; a neutral outlined cleanup button, disabled until a cleanup is supported. Show estimates, file sizes and measured available-capacity changes as different things. Whole-row disclosure targets are at least 28 pt tall with a pointing cursor. Preserve page, selection and scroll context. Measurements and bars update directly; motion explains navigation, selection or disclosure and must handle reversal.

Before a new screen or visual change, make a throwaway appearance-only prototype and agree it before building. Keep every prototype and native version beside the earlier ones instead of overwriting them.

Accessibility, keyboard and appearance trial gates are deferred for this personal app until a public release. That does not remove system behaviour, and never change OS settings to manufacture a pass.

## Tooling and docs

Local agent tooling folders (`.bro-code/`, `.agents/`, `.claude/`, `.codex/`) are ignored and not part of this repository. Follow the project workflow in this file and in [CONTRIBUTING.md](CONTRIBUTING.md); keep task state in your own records, not in the repository.

Update the consumer docs when behaviour changes, follow the page rules in the [documentation index](docs/README.md), and keep historical evidence intact.
