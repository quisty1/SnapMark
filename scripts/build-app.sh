#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$ROOT/dist}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"
cd "$ROOT"
swift build -c release --product SnapMark
BIN="$(swift build -c release --show-bin-path)"
APP="$DEST/SnapMark.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SnapMark" "$APP/Contents/MacOS/SnapMark"
/usr/bin/swift scripts/make-icon.swift "$ROOT/.build/SnapMark.iconset"
/usr/bin/iconutil -c icns "$ROOT/.build/SnapMark.iconset" -o "$APP/Contents/Resources/SnapMark.icns"
python3 - "$APP/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump({
        'CFBundleName':'SnapMark','CFBundleDisplayName':'SnapMark',
        'CFBundleIdentifier':'local.snapmark.app','CFBundleExecutable':'SnapMark',
        'CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0.0',
        'CFBundleVersion':'1','LSMinimumSystemVersion':'14.0',
        'LSUIElement':True,'NSHighResolutionCapable':True,
        'CFBundleIconFile':'SnapMark','CFBundleDevelopmentRegion':'en',
        'CFBundleLocalizations':['en','ru'],
        'NSScreenCaptureUsageDescription':'SnapMark captures the screen only when you request a screenshot. Images stay on this Mac.'
    },f)
PY
/usr/bin/codesign --force --sign - --timestamp=none "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP" "$DEST/SnapMark.zip"
printf 'Built: %s\nArchive: %s\n' "$APP" "$DEST/SnapMark.zip"
