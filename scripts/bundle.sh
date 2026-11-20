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
# A stable signature keeps Keychain "Always Allow" valid across rebuilds. Prefer a real Apple identity,
# then the self-signed "Onyx Local Signing" (scripts/make-signing-cert.sh), else ad-hoc (prompts again
# after each rebuild). SIGN_IDENTITY / SIGN_KEYCHAIN override.
KC_ARGS=(); [ -n "${SIGN_KEYCHAIN:-}" ] && KC_ARGS=(--keychain "$SIGN_KEYCHAIN")
ID="${SIGN_IDENTITY:-}"
if [ -z "$ID" ]; then
  ID=$(security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p;s/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$ID" ] && security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} 2>/dev/null | grep -q '"Onyx Local Signing"'; then ID="Onyx Local Signing"; fi
if [ -n "$ID" ] && codesign --force --deep ${KC_ARGS[@]+"${KC_ARGS[@]}"} --sign "$ID" "$APP" >/dev/null 2>&1; then
  echo "Signed with \"$ID\""
else
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
  echo "Signed ad hoc (run scripts/make-signing-cert.sh once for a stable signature)"
fi
echo "Built $APP"
