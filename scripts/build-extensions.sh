#!/bin/bash
# Build Onyx's app extensions into an app bundle's Contents/PlugIns, without Xcode projects:
#   OnyxSafari.appex  Safari Web Extension "Clip to Onyx" (toolbar button + context menu)
#   OnyxShare.appex   Share menu item "Onyx" (Safari's Share button, other apps)
# Each is a small Swift executable whose entry point is NSExtensionMain, an Info.plist, and
# (Safari) the WebExtension resources. Signing happens in bundle.sh (sandbox entitlement).
#   scripts/build-extensions.sh build/Onyx.app [release|debug]
# UNIVERSAL=1 builds arm64 + x86_64; ARCH=arm64|x86_64 one slice; default this machine.
set -euo pipefail
APP="$1"
CONFIG="${2:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
UNIVERSAL="${UNIVERSAL:-0}"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
APP_ID="org.kennethreitz.onyx"
MIN_OS="14.0"
if [ "$UNIVERSAL" = 1 ]; then ARCHS=(arm64 x86_64)
elif [ -n "${ARCH:-}" ]; then ARCHS=("$ARCH")
else ARCHS=("$(uname -m)"); fi
OPT=(-O); [ "$CONFIG" = debug ] && OPT=(-Onone -g)
WORK="$ROOT/.build/extensions"
rm -rf "$WORK"; mkdir -p "$WORK" "$APP/Contents/PlugIns"

# compile <module> <output> <sources…>: one binary per arch, lipo'd together.
compile() {
  local module="$1" out="$2"; shift 2
  local slices=()
  for a in "${ARCHS[@]}"; do
    local o="$WORK/$module-$a"
    xcrun swiftc "${OPT[@]}" -parse-as-library -module-name "$module" \
      -target "$a-apple-macos$MIN_OS" -sdk "$(xcrun --show-sdk-path --sdk macosx)" \
      -Xlinker -e -Xlinker _NSExtensionMain \
      "$@" -o "$o"
    slices+=("$o")
  done
  lipo -create "${slices[@]}" -output "$out"
}

# plist <file> <bundle-id> <executable> <display name> <NSExtension dict xml>
plist() {
  cat > "$1" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>$2</string>
  <key>CFBundleExecutable</key><string>$3</string>
  <key>CFBundleName</key><string>$3</string>
  <key>CFBundleDisplayName</key><string>$4</string>
  <key>CFBundlePackageType</key><string>XPC!</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>NSHumanReadableCopyright</key><string>Onyx is free software under the AGPL-3.0.</string>
  <key>NSExtension</key>
$5
</dict>
</plist>
PLIST
  plutil -lint "$1" >/dev/null
}

# Safari Web Extension
SAFARI="$APP/Contents/PlugIns/OnyxSafari.appex"
rm -rf "$SAFARI"; mkdir -p "$SAFARI/Contents/MacOS" "$SAFARI/Contents/Resources/images"
compile OnyxSafari "$SAFARI/Contents/MacOS/OnyxSafari" \
  "$ROOT/Extensions/Safari/SafariWebExtensionHandler.swift" "$ROOT/Sources/OnyxCore/ClipURL.swift" \
  -framework SafariServices -framework AppKit
plist "$SAFARI/Contents/Info.plist" "$APP_ID.SafariExtension" OnyxSafari "Clip to Onyx" "  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.Safari.web-extension</string>
    <key>NSExtensionPrincipalClass</key><string>SafariWebExtensionHandler</string>
  </dict>"
cp "$ROOT/Extensions/Safari/Resources/background.js" "$SAFARI/Contents/Resources/"
sed "s/__VERSION__/$VERSION/" "$ROOT/Extensions/Safari/Resources/manifest.json" > "$SAFARI/Contents/Resources/manifest.json"
ICNS="$ROOT/Resources/AppIcon.icns"
# Manifest icons (full-color stone) and toolbar glyphs (monochrome O, tinted by Safari) are
# committed; regenerate with `swift scripts/make-extension-icons.swift`.
cp "$ROOT"/Extensions/Safari/Resources/images/*.png "$SAFARI/Contents/Resources/images/"
cp "$ICNS" "$SAFARI/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$SAFARI/Contents/Info.plist"

# Share extension
SHARE="$APP/Contents/PlugIns/OnyxShare.appex"
rm -rf "$SHARE"; mkdir -p "$SHARE/Contents/MacOS" "$SHARE/Contents/Resources"
compile OnyxShare "$SHARE/Contents/MacOS/OnyxShare" \
  "$ROOT/Extensions/Share/ShareViewController.swift" "$ROOT/Sources/OnyxCore/ClipURL.swift" \
  -framework AppKit -framework UniformTypeIdentifiers
plist "$SHARE/Contents/Info.plist" "$APP_ID.ShareExtension" OnyxShare "Onyx" "  <dict>
    <key>NSExtensionPointIdentifier</key><string>com.apple.share-services</string>
    <key>NSExtensionPrincipalClass</key><string>ShareViewController</string>
    <key>NSExtensionAttributes</key>
    <dict>
      <key>NSExtensionActivationRule</key>
      <dict>
        <key>NSExtensionActivationSupportsWebURLWithMaxCount</key><integer>1</integer>
        <key>NSExtensionActivationSupportsText</key><true/>
      </dict>
    </dict>
  </dict>"
cp "$ICNS" "$SHARE/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$SHARE/Contents/Info.plist"

echo "Extensions: $(cd "$APP/Contents/PlugIns" && ls | tr '\n' ' ')($(lipo -archs "$SAFARI/Contents/MacOS/OnyxSafari"))"
