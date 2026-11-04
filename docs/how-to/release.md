---
audience: maintainer
---

# Publish a release

Use this page to publish a Disk Cleaner version as a GitHub release.

1. In `CHANGELOG.md`, move the `## Unreleased` entries under a new `## X.Y.Z - YYYY-MM-DD` heading and leave `## Unreleased` empty. The Help Book's What's new page is the changelog section for the version, so the heading must exist before you tag. Set the default `VERSION` in `scripts/build-and-package.sh` (the workflow passes the tag's version) and the Xcode host plists to the same version.
2. Commit, then tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
3. The Release workflow runs `scripts/build-and-package.sh` (tests, release build, the generated Help Book copied into both apps, ad-hoc signing of `Disk Cleaner.app` and `Disk Cleaner Preview.app`), builds `DiskCleaner-vX.Y.Z.dmg` (read-only, both apps plus an `Applications` link), zips both as `DiskCleaner-vX.Y.Z.zip`, writes a `.sha256` file for each and creates the GitHub release with the changelog section. Versions below 1.0 are marked prerelease.
4. Verify a download: `gh release download vX.Y.Z -R aikongen/disk-cleaner -p 'DiskCleaner-*'` then `shasum -a 256 -c DiskCleaner-vX.Y.Z.dmg.sha256` (and the `.zip.sha256`). Downloading with `gh` avoids macOS quarantine; the apps are not notarized.
