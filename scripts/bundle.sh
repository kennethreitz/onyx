#!/bin/bash
# Wrap the SwiftPM binary into a real macOS app bundle: build/Onyx.app
set -euo pipefail
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="$ROOT/.build/$CONFIG/Onyx"
APP="$ROOT/build/Onyx.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Onyx"
rsync -a --delete "$ROOT/Resources/" "$APP/Contents/Resources/OnyxResources/"
[ -f "$ROOT/build/Onyx.icns" ] && cp "$ROOT/build/Onyx.icns" "$APP/Contents/Resources/Onyx.icns"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.0)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Onyx</string>
  <key>CFBundleDisplayName</key><string>Onyx</string>
  <key>CFBundleIdentifier</key><string>org.kennethreitz.onyx</string>
  <key>CFBundleExecutable</key><string>Onyx</string>
  <key>CFBundleIconFile</key><string>Onyx</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict></array>
</dict>
</plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
