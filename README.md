# Disk Cleaner

See what fills your Mac, choose exactly what goes, and give your AI agent an honest answer about free space.

<p align="center">
  <img src="assets/hero.png" alt="Disk Cleaner" width="860">
</p>

<p align="center">
  <a href="https://github.com/aikongen/disk-cleaner/releases"><img src="https://img.shields.io/github/v/release/aikongen/disk-cleaner?include_prereleases&label=release&style=flat&color=6941C6" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS_14%2B_%C2%B7_Apple_silicon-1F1A33?style=flat&logo=apple&logoColor=white" alt="macOS 14 or later on Apple silicon">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-7F56D9?style=flat" alt="MIT license"></a>
</p>

Most disk tools either draw you a chart or clean "junk" on their own terms. Disk Cleaner shows you what is really there, lets you choose exactly what goes, and tells an AI agent the truth too. It is a personal, local macOS app: your data stays on your Mac.

## What you get

<table>
  <tr>
    <td width="50%" valign="top">
      <img src="assets/screenshot-overview.png" alt="Overview: disk capacity beside the sizes of the scanned folder">
      <br><b>See what fills your disk</b>
      <br>Capacity and the sizes of the folder you scanned, side by side. Estimates, sizes and measured changes stay separate, and unknown stays unknown.
      <br>The Make room for work card and the recent cleanup row are a concept preview with example data; no cleanup category is enabled yet, and the real app shows a disabled Clean up button.
    </td>
    <td width="50%" valign="top">
      <img src="assets/screenshot-browse.png" alt="Browse files: a folder opened from the saved scan, with one item checked">
      <br><b>Find it without rescanning</b>
      <br>The scan is kept. Click into folders, step back with breadcrumbs, search, and sort by Size, Name or Modified.
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <img src="assets/screenshot-trash-review.png" alt="Review before moving to Trash: the exact paths that will move">
      <br><b>Choose exactly, then check</b>
      <br>Check the items you want and read their full paths first. Move to Trash moves those paths and nothing else, with an outcome for each.
    </td>
    <td width="50%" valign="top">
      <img src="assets/screenshot-settings.png" alt="Settings: atmosphere, remember last scan and scan history">
      <br><b>Keep it your way</b>
      <br>A Teal or Violet atmosphere, remember the last scan, and keep 5, 10 or 30 scans.
    </td>
  </tr>
</table>

Screenshots show the built-in preview with example data.

**It never deletes anything permanently and never cleans on its own. It moves exactly the items you chose to the Trash.**

## Get it

1. Download the latest `DiskCleaner-vX.Y.Z.zip` from the [releases page](https://github.com/aikongen/disk-cleaner/releases).
2. Unzip it and move `Disk Cleaner.app` to your Applications folder. The zip also holds `Disk Cleaner Preview.app`, which shows every screen with example data and cannot touch your disk.
3. The app is ad-hoc signed and not notarized, so macOS blocks the first open. Right-click the app and choose **Open**, then confirm. Or open **System Settings > Privacy & Security** and choose **Open Anyway**.

Needs macOS 14 or later. It has been built and tested only on Apple silicon.

## Use it

1. Open the app and choose a folder to scan. Cancel keeps your previous result.
2. **Overview** shows disk capacity beside the folder's recorded sizes.
3. **Browse files** lets you click into folders, search, sort, and tick the items you want.
4. **Review for Trash** shows their exact paths. **Move to Trash** moves those and nothing else, with an outcome for each.
5. **Cleanups** lists past agent requests and their outcomes. Settings opens with the gear or Command-comma.

Space returns only when you empty the Trash, and Finder's Put Back is not promised. The [first scan tutorial](docs/tutorials/first-scan.md) walks through it and covers the remaining limits.

## For AI agents

An agent asks for a target amount of available space through a same-user command line tool inside the app. It cannot pass paths, commands or rules. No cleanup category is enabled yet, so a request for more than is free answers `insufficient` rather than guessing. The [automation contract](docs/reference/automation-contract.md) lists every command, field and status.

## Documentation

See the [documentation index](docs/README.md). Changes are in the [changelog](CHANGELOG.md); security reports go through [SECURITY.md](SECURITY.md). Disk Cleaner is released under the [MIT License](LICENSE).

## Maintainers and contributors

Building from source, tests and pull requests: [maintainer guide](docs/maintainer-guide.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

<p align="center">
  <a href="https://github.com/aikongen"><img src="assets/made-with-love-aikongen.svg" alt="Made with love by Aikongen" height="40"></a>
</p>
