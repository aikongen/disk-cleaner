#!/usr/bin/env bash
# Builds DiskCleaner.help (an Apple Help Book) from the consumer docs.
# Usage: scripts/make-help-book.sh [output-parent-dir]   (default: artifacts/)
# Markdown is converted by scripts/help-book/md2html.py (no pandoc or third-party packages needed).
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_PARENT="${1:-$PACKAGE_ROOT/artifacts}"
VERSION="${DISK_CLEANER_VERSION:-0.1.2}"
BOOK="$OUT_PARENT/DiskCleaner.help"
LPROJ="$BOOK/Contents/Resources/English.lproj"
BOOK_ID="${2:-com.aikongen.diskcleaner.help}"

[[ "$(uname -s)" == Darwin ]] || { echo "The Help Book index needs macOS (hiutil)." >&2; exit 2; }

rm -rf "$BOOK"
mkdir -p "$LPROJ"

cat > "$BOOK/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleIdentifier</key><string>$BOOK_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>Disk Cleaner Help</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleSignature</key><string>hbwr</string>
  <key>CFBundleVersion</key><string>3</string>
  <key>HPDBookAccessPath</key><string>index.html</string>
  <key>HPDBookIndexPath</key><string>DiskCleaner.helpindex</string>
  <key>HPDBookTitle</key><string>Disk Cleaner Help</string>
  <key>HPDBookType</key><string>3</string>
</dict>
</plist>
PLIST
plutil -lint "$BOOK/Contents/Info.plist" >/dev/null

python3 -I "$PACKAGE_ROOT/scripts/help-book/build.py" "$PACKAGE_ROOT" "$LPROJ" "$VERSION"

hiutil -C -a -s en -f "$LPROJ/DiskCleaner.helpindex" "$LPROJ"
[[ -s "$LPROJ/DiskCleaner.helpindex" ]] || { echo "Help index was not created." >&2; exit 1; }
echo "Built $BOOK"
