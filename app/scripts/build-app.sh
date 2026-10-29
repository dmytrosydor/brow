#!/bin/sh
# Builds build/brow.app: release binaries (brow + brow-hook), icon, Info.plist,
# ad-hoc signature. Usage: scripts/build-app.sh [version]
set -eu

cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
APP=build/brow.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Brow" "$APP/Contents/MacOS/brow"
cp "$BIN/brow-hook" "$APP/Contents/MacOS/brow-hook"

ICONSET="$(mktemp -d)/AppIcon.iconset"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>brow</string>
  <key>CFBundleDisplayName</key><string>brow</string>
  <key>CFBundleIdentifier</key><string>com.dmytrosydor.brow</string>
  <key>CFBundleExecutable</key><string>brow</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Dmytro Sydor</string>
</dict>
</plist>
PLIST

# Ad-hoc signature: enough to run locally and for launch at login.
codesign --force --sign - "$APP/Contents/MacOS/brow-hook"
codesign --force --sign - "$APP"
echo "built $APP ($VERSION)"
