#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${1:-$PACKAGE_ROOT/artifacts}"
VERSION="${DISK_CLEANER_VERSION:-0.1.0}"

case "$(uname -s)" in
  Darwin) ;;
  *) echo "Build and packaging require macOS." >&2; exit 2 ;;
esac

case "$DIST_DIR" in
  "$PACKAGE_ROOT"/*) ;;
  *) echo "Output must stay inside the isolated package workspace: $PACKAGE_ROOT" >&2; exit 2 ;;
esac

cd "$PACKAGE_ROOT"
swift test
swift build -c release --product DiskCleanerApp
swift build -c release --product disk-cleanerctl
BIN_DIR="$(swift build -c release --show-bin-path)"

[[ -x "$BIN_DIR/DiskCleanerApp" ]] || { echo "Missing release app executable." >&2; exit 1; }
[[ -x "$BIN_DIR/disk-cleanerctl" ]] || { echo "Missing release CLI executable." >&2; exit 1; }
mkdir -p "$DIST_DIR"

# The Help Book is generated from the consumer docs; each app gets its own book id.
HELP_ID="com.aikongen.diskcleaner.help"
"$PACKAGE_ROOT/scripts/make-help-book.sh" "$DIST_DIR/.help-normal" "$HELP_ID"
"$PACKAGE_ROOT/scripts/make-help-book.sh" "$DIST_DIR/.help-preview" "$HELP_ID.preview"

write_info_plist() {
  local plist_path="$1" bundle_name="$2" bundle_id="$3" demo_mode="$4" help_id="$5"
  cat > "$plist_path" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>DiskCleanerApp</string>
  <key>CFBundleHelpBookFolder</key><string>DiskCleaner.help</string>
  <key>CFBundleHelpBookName</key><string>$help_id</string>
  <key>CFBundleIconFile</key><string>DiskCleaner</string>
  <key>CFBundleIdentifier</key><string>$bundle_id</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleName</key><string>$bundle_name</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
$demo_mode
</dict>
</plist>
PLIST
  /usr/libexec/PlistBuddy -c 'Print' "$plist_path" >/dev/null
}

package_app() {
  local app_name="$1" bundle_id="$2" demo_mode="$3" help_dir="$4" help_id="$5"
  local final_app="$DIST_DIR/$app_name.app"
  local stage_dir app_dir demo_keys
  stage_dir="$(mktemp -d "$DIST_DIR/.package.XXXXXX")"
  app_dir="$stage_dir/$app_name.app"
  mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"

  install -m 755 "$BIN_DIR/DiskCleanerApp" "$app_dir/Contents/MacOS/DiskCleanerApp"
  install -m 755 "$BIN_DIR/disk-cleanerctl" "$app_dir/Contents/MacOS/disk-cleanerctl"
  install -m 644 "$PACKAGE_ROOT/assets/icon/DiskCleaner.icns" "$app_dir/Contents/Resources/DiskCleaner.icns"
  cp -R "$DIST_DIR/.help-$help_dir/DiskCleaner.help" "$app_dir/Contents/Resources/DiskCleaner.help"
  printf 'APPL????' > "$app_dir/Contents/PkgInfo"

  demo_keys=""
  if [[ "$demo_mode" == true ]]; then
    demo_keys='  <key>DiskCleanerDemoMode</key><true/>
  <key>DiskCleanerDemoScene</key><string>overview</string>'
  fi
  write_info_plist "$app_dir/Contents/Info.plist" "$app_name" "$bundle_id" "$demo_keys" "$help_id"

  codesign --force --sign - --timestamp=none --identifier "$bundle_id" "$app_dir"
  codesign --verify --deep --strict --verbose=2 "$app_dir"

  # Replacing these two named bundles inside this task-local artifact directory is intentional.
  rm -rf "$final_app"
  mv "$app_dir" "$final_app"
  rmdir "$stage_dir"
}

package_app "Disk Cleaner" "com.aikongen.diskcleaner" false normal "$HELP_ID"
package_app "Disk Cleaner Preview" "com.aikongen.diskcleaner.preview" true preview "$HELP_ID.preview"
rm -rf "$DIST_DIR/.help-normal" "$DIST_DIR/.help-preview"

# Drag-to-install disk image: both apps plus an Applications link, compressed and read-only.
DMG_PATH="$DIST_DIR/DiskCleaner-v$VERSION.dmg"
DMG_STAGE="$(mktemp -d "$DIST_DIR/.dmg.XXXXXX")"
DMG_RW="$DMG_STAGE/rw.dmg"
cp -R "$DIST_DIR/Disk Cleaner.app" "$DIST_DIR/Disk Cleaner Preview.app" "$DMG_STAGE/"
ln -s /Applications "$DMG_STAGE/Applications"
cp "$PACKAGE_ROOT/assets/icon/DiskCleaner.icns" "$DMG_STAGE/.VolumeIcon.icns"
hdiutil create -quiet -volname "Disk Cleaner" -srcfolder "$DMG_STAGE" -fs HFS+ -format UDRW -ov "$DMG_RW"
DMG_MOUNT="$DMG_STAGE/mount"
mkdir "$DMG_MOUNT"
hdiutil attach -quiet -nobrowse -noverify -mountpoint "$DMG_MOUNT" "$DMG_RW"
if command -v SetFile >/dev/null 2>&1; then SetFile -a C "$DMG_MOUNT" || true; fi
hdiutil detach -quiet "$DMG_MOUNT"
rm -f "$DMG_PATH"
hdiutil convert -quiet "$DMG_RW" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -rf "$DMG_STAGE"
(cd "$DIST_DIR" && shasum -a 256 "DiskCleaner-v$VERSION.dmg" > "DiskCleaner-v$VERSION.dmg.sha256")

(
  cd "$PACKAGE_ROOT"
  find CONTRACT.md Package.swift README.md CHANGELOG.md docs Sources Tests scripts/build-and-package.sh scripts/make-help-book.sh scripts/help-book assets/icon/DiskCleaner.icns -type f ! -name .DS_Store -print | LC_ALL=C sort | while IFS= read -r file; do
    shasum -a 256 "$file"
  done
) > "$DIST_DIR/SOURCE-MANIFEST.sha256"

shasum -a 256 "$DIST_DIR/Disk Cleaner.app/Contents/MacOS/DiskCleanerApp" \
  "$DIST_DIR/Disk Cleaner.app/Contents/MacOS/disk-cleanerctl" \
  "$DIST_DIR/Disk Cleaner Preview.app/Contents/MacOS/DiskCleanerApp" \
  "$DIST_DIR/Disk Cleaner Preview.app/Contents/MacOS/disk-cleanerctl" \
  > "$DIST_DIR/EXECUTABLES.sha256"

{
  printf 'host=%s\n' "$(hostname)"
  printf 'macos=%s\n' "$(sw_vers -productVersion)"
  printf 'swift=%s\n' "$(swift --version | head -n 1)"
  printf 'git_revision=%s\n' "$(git -C "$PACKAGE_ROOT" rev-parse HEAD 2>/dev/null || echo none)"
  printf 'swift_test=PASS (counts in the swift test output)\n'
  printf 'swift_build_DiskCleanerApp=PASS\n'
  printf 'swift_build_disk-cleanerctl=PASS\n'
  printf 'codesign_verify_both_bundles=PASS\n'
  printf 'minimum_macos=14.0\n'
  printf 'source_manifest_sha256=%s\n' "$(shasum -a 256 "$DIST_DIR/SOURCE-MANIFEST.sha256" | awk '{print $1}')"
} > "$DIST_DIR/BUILD-INFO.txt"

printf 'Built and signed apps in %s\n' "$DIST_DIR"
