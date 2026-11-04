#!/usr/bin/env bash
# Regenerate every icon-derived asset from one 1024x1024 PNG:
#   scripts/make-icon-assets.sh path/to/icon-1024.png
# Writes assets/icon/ (png, iconset, icns), assets/icon.png, the Xcode AppIcon
# catalog and the README hero (assets/hero.png).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${1:?usage: make-icon-assets.sh <source-1024.png>}"
[[ -f "$SRC" ]] || { echo "Missing source: $SRC" >&2; exit 2; }
[[ "$(sips -g pixelWidth -g pixelHeight "$SRC" | awk '/pixel/{printf "%s ", $2}')" == "1024 1024 " ]] \
  || { echo "Source must be 1024x1024." >&2; exit 2; }
command -v magick >/dev/null || { echo "ImageMagick (magick) is required." >&2; exit 2; }

ICON="$ROOT/assets/icon"
SET="$ICON/AppIcon.iconset"
CAT="$ROOT/xcode/DiskCleanerHost/Assets.xcassets/AppIcon.appiconset"
FONT_REG="${HERO_FONT:-Helvetica}"
FONT_BOLD="${HERO_FONT_BOLD:-Helvetica-Bold}"
PROMISE="See what fills your Mac, choose exactly what goes, and give your AI agent an honest answer about free space."

mkdir -p "$ICON" "$SET" "$CAT"
[[ "$(cd "$(dirname "$SRC")" && pwd)/$(basename "$SRC")" == "$ICON/icon-1024.png" ]] || cp "$SRC" "$ICON/icon-1024.png"
rm -f "$SET"/*.png "$CAT"/*.png

# Masked master: macOS icon grid, 824 px shape centred on a 1024 canvas, corner radius 185.4, soft shadow.
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
magick "$ICON/icon-1024.png" -resize 824x824 \
  \( -size 824x824 xc:black -fill white -draw "roundrectangle 0,0 823,823 185.4,185.4" \) \
  -alpha off -compose CopyOpacity -composite "$TMP/shape.png"
magick "$TMP/shape.png" \( +clone -background black -shadow 35x10+0+10 \) -reverse \
  -background none -layers merge +repage -gravity center -extent 1024x1024 "$TMP/masked-1024.png"
mk() { sips -z "$1" "$1" "$TMP/masked-1024.png" --out "$2" >/dev/null; }
mk 16 "$SET/icon_16x16.png";   mk 32 "$SET/icon_16x16@2x.png"
mk 32 "$SET/icon_32x32.png";   mk 64 "$SET/icon_32x32@2x.png"
mk 128 "$SET/icon_128x128.png"; mk 256 "$SET/icon_128x128@2x.png"
mk 256 "$SET/icon_256x256.png"; mk 512 "$SET/icon_256x256@2x.png"
mk 512 "$SET/icon_512x512.png"; cp "$TMP/masked-1024.png" "$SET/icon_512x512@2x.png"
iconutil -c icns "$SET" -o "$ICON/DiskCleaner.icns"
file "$ICON/DiskCleaner.icns" | grep -q "Mac OS X icon"
mk 256 "$ROOT/assets/icon.png"

# Xcode asset catalog (shared by the app and the fixture preview targets).
cp "$SET"/*.png "$CAT/"
python3 - "$CAT" <<'PY'
import json, sys
imgs = [{"filename": f"icon_{pt}x{pt}{'@2x' if sc == 2 else ''}.png", "idiom": "mac",
         "scale": f"{sc}x", "size": f"{pt}x{pt}"} for pt in (16, 32, 128, 256, 512) for sc in (1, 2)]
json.dump({"images": imgs, "info": {"author": "xcode", "version": 1}},
          open(sys.argv[1] + "/Contents.json", "w"), indent=2)
PY

# README hero: 1600x600, dark violet canvas, icon with a soft glow, title, promise, capacity bar.
W=1600; H=600; S=380; IX=150; IY=110
magick -size ${W}x${H} xc:'#17122B' \
  \( -size ${W}x${H} xc:none -fill 'rgba(124,92,230,0.55)' -draw "circle $((IX+S/2)),$((IY+S/2)) $((IX+S/2+S/2+10)),$((IY+S/2))" -blur 0x70 \) -compose over -composite \
  \( "$ICON/icon-1024.png" -resize ${S}x${S} \( -size ${S}x${S} xc:black -fill white -draw "roundrectangle 0,0 $((S-1)),$((S-1)) 86,86" \) -alpha off -compose CopyOpacity -composite \) -geometry +${IX}+${IY} -compose over -composite \
  -font "$FONT_BOLD" -pointsize 92 -fill '#F5F2FF' -annotate +640+260 "Disk Cleaner" \
  -font "$FONT_REG" -pointsize 31 -fill '#B7AFD6' -interline-spacing 12 \
  -annotate +644+330 "See what fills your Mac, choose exactly what goes,\nand give your AI agent an honest answer about free space." \
  -fill '#3BB2A6' -draw "roundrectangle 644,440 884,452 6,6" \
  -fill '#6699DB' -draw "roundrectangle 892,440 1032,452 6,6" \
  -fill '#D4A847' -draw "roundrectangle 1040,440 1124,452 6,6" \
  -fill '#CC829C' -draw "roundrectangle 1132,440 1180,452 6,6" \
  -fill 'rgba(255,255,255,0.10)' -draw "roundrectangle 1188,440 1380,452 6,6" \
  "$ROOT/assets/hero.png"
echo "Icon assets regenerated from $SRC"
