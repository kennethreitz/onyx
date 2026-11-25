#!/bin/bash
# Wrap the SwiftPM binary into a real macOS app bundle: build/Onyx.app
set -euo pipefail
CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIVERSAL="${UNIVERSAL:-0}"
ARCH="${ARCH:-}"
if [ "$UNIVERSAL" = 1 ]; then
  BIN="$ROOT/.build/universal/Onyx"
else
  SHOW_ARGS=(-c "$CONFIG")
  if [ -n "$ARCH" ]; then
    SHOW_ARGS+=(--arch "$ARCH")
  fi
  SHOW=$(swift build "${SHOW_ARGS[@]}" --show-bin-path 2>/dev/null || true)
  if [ -n "$SHOW" ] && [ -x "$SHOW/Onyx" ]; then
    BIN="$SHOW/Onyx"
  else
    BIN="$ROOT/.build/$CONFIG/Onyx"
  fi
fi
if [ ! -x "$BIN" ]; then
  echo "error: missing binary at $BIN" >&2
  exit 1
fi
if [ "$UNIVERSAL" = 1 ]; then
  info=$(lipo -info "$BIN" 2>/dev/null || true)
  case "$info" in
    *arm64*) ;;
    *) echo "error: universal build is missing arm64 ($info)" >&2; exit 1 ;;
  esac
  case "$info" in
    *x86_64*) ;;
    *) echo "error: universal build is missing x86_64 ($info)" >&2; exit 1 ;;
  esac
fi
APP="$ROOT/build/Onyx.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Onyx"
rsync -a --delete --exclude AppIcon.icns "$ROOT/Resources/" "$APP/Contents/Resources/OnyxResources/"
cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.1.18)"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Onyx</string>
  <key>CFBundleDisplayName</key><string>Onyx</string>
  <key>CFBundleIdentifier</key><string>org.kennethreitz.onyx</string>
  <key>CFBundleExecutable</key><string>Onyx</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.productivity</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSMicrophoneUsageDescription</key><string>Onyx records audio into your notes when you choose Record Audio.</string>
  <key>NSSpeechRecognitionUsageDescription</key><string>Onyx transcribes your recordings on this Mac.</string>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoadsInWebContent</key><true/></dict>
  <key>CFBundleURLTypes</key>
  <array><dict>
    <key>CFBundleURLName</key><string>org.kennethreitz.onyx</string>
    <key>CFBundleURLSchemes</key><array><string>onyx</string></array>
  </dict></array>
  <key>CFBundleDocumentTypes</key>
  <array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Editor</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict></array>
</dict>
</plist>
PLIST
# App extensions (Safari "Clip to Onyx", Share menu) → Contents/PlugIns. SKIP_EXTENSIONS=1 skips them.
if [ "${SKIP_EXTENSIONS:-0}" != 1 ]; then
  UNIVERSAL="$UNIVERSAL" ARCH="$ARCH" "$ROOT/scripts/build-extensions.sh" "$APP" "$CONFIG"
fi
# A stable signature keeps Keychain "Always Allow" valid across rebuilds. Prefer a real Apple identity,
# then the self-signed "Onyx Local Signing" (scripts/make-signing-cert.sh), else ad-hoc (prompts again
# after each rebuild). SIGN_IDENTITY / SIGN_KEYCHAIN override.
KC_ARGS=(); [ -n "${SIGN_KEYCHAIN:-}" ] && KC_ARGS=(--keychain "$SIGN_KEYCHAIN")
ID="${SIGN_IDENTITY:-}"
if [ -z "$ID" ]; then
  ID=$(security find-identity -v -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p;s/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -1)
fi
if [ -z "$ID" ] && security find-identity -p codesigning ${SIGN_KEYCHAIN:+"$SIGN_KEYCHAIN"} 2>/dev/null | grep -q '"Onyx Local Signing"'; then ID="Onyx Local Signing"; fi
# Extensions are signed first, each with the App Sandbox entitlement extensions require, then
# the app (not --deep, which would re-sign the extensions without their entitlements).
sign_all() {
  local id="$1"; shift
  local x
  for x in "$APP"/Contents/PlugIns/*.appex; do
    [ -d "$x" ] || continue
    codesign --force --timestamp=none "$@" --entitlements "$ROOT/Extensions/sandbox.entitlements" --sign "$id" "$x" >/dev/null 2>&1 || return 1
  done
  codesign --force --timestamp=none "$@" --sign "$id" "$APP" >/dev/null 2>&1
}
if [ -n "$ID" ] && sign_all "$ID" ${KC_ARGS[@]+"${KC_ARGS[@]}"}; then
  echo "Signed with \"$ID\""
else
  sign_all - || true
  echo "Signed ad hoc (run scripts/make-signing-cert.sh once for a stable signature)"
fi
case "$ID" in
  "Apple Development:"*|"Developer ID Application:"*) ;;
  *) [ -d "$APP/Contents/PlugIns/OnyxSafari.appex" ] && echo "Note: Safari lists \"Clip to Onyx\" only with Allow Unsigned Extensions on until Onyx is signed by an Apple Development or Developer ID certificate (see docs/web-clipper.md)." ;;
esac
echo "Built $APP"
echo "Binary: $(lipo -info "$APP/Contents/MacOS/Onyx")"
file "$APP/Contents/MacOS/Onyx"
