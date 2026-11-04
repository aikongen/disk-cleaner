---
audience: consumer
---

# Disk Cleaner docs

For the person using Disk Cleaner on their own Mac, for an agent calling its command line tool, and for maintainers changing the source. Each page names its audience in front matter and opens with the task it serves. Nothing is described as existing unless it exists today; unfinished work is labelled "planned" or "in progress". Folders follow Diátaxis: tutorials teach by doing, how-to guides solve one task, explanations say why, references list facts.

## Tutorials

- [Open Disk Cleaner, scan a folder and review what to move](tutorials/first-scan.md) opens the app, browses a scan and walks the Trash review.

## How-to guides

- [Publish a release](how-to/release.md) tags a version and checks the download checksum (maintainer).

## Explanation

- [Architecture and quality path](explanation/architecture-and-readiness.md) says how the parts fit and what must improve next (maintainer).
- [Appearance](explanation/appearance.md) covers the two window atmospheres and the colour rules (maintainer).

## Reference

- [Automation contract](reference/automation-contract.md) lists the `disk-cleanerctl` commands, JSON fields and statuses.

## Maintainer

- [Maintainer guide](maintainer-guide.md) covers getting the source, build, test, the example-data preview, fixture isolation and evidence conventions.
