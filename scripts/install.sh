#!/bin/bash
# Install (or uninstall) build/Onyx.app into $INSTALL_DIR (default /Applications).
#   scripts/install.sh install | uninstall
# Env: INSTALL_DIR, DESTDIR (staging prefix), NO_QUIT=1, RELAUNCH=1,
#      UNIVERSAL, ONE_ARCH, ARCH (so a one-arch install is not warned as "not universal").
# A running Onyx is asked to quit (never force-killed) only when the target is the
# real /Applications with no DESTDIR, so test installs never touch a running app.
set -euo pipefail
ACTION="${1:-install}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="org.kennethreitz.onyx"
INSTALL_DIR="${INSTALL_DIR:-/Applications}"
DESTDIR="${DESTDIR:-}"
DIR="${DESTDIR}${INSTALL_DIR%/}"
TARGET="$DIR/Onyx.app"
SRC="$ROOT/build/Onyx.app"

may_quit() {
  [ "${NO_QUIT:-0}" != 1 ] && [ -z "$DESTDIR" ] && [ "${INSTALL_DIR%/}" = /Applications ]
}
is_running() {
  [ "$(osascript -e "application id \"$BUNDLE_ID\" is running" 2>/dev/null)" = true ]
}

WAS_RUNNING=0
quit_onyx() {
  if ! may_quit; then
    echo "Not quitting Onyx (target is $DIR, not /Applications, or NO_QUIT=1)."
    return
  fi
  is_running || return 0
  WAS_RUNNING=1
  echo "Onyx is running; asking it to quit (it saves first)…"
  osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in $(seq 1 60); do is_running || break; sleep 0.25; done
  if is_running; then
    echo "error: Onyx is still running after 15s; quit it and run make install again." >&2
    exit 1
  fi
  echo "Quit Onyx."
}

case "$ACTION" in
  install)
    [ -d "$SRC" ] || { echo "error: missing $SRC" >&2; exit 1; }
    mkdir -p "$DIR"
    quit_onyx
    TMP="$DIR/.Onyx.app.installing.$$"
    OLD="$DIR/.Onyx.app.old.$$"
    rm -rf "$TMP" "$OLD"
    trap 'rm -rf "$TMP"' EXIT
    ditto "$SRC" "$TMP"
    if [ -e "$TARGET" ]; then
      mv "$TARGET" "$OLD"
      if ! mv "$TMP" "$TARGET"; then
        mv "$OLD" "$TARGET"
        echo "error: could not move the new app into $TARGET" >&2
        exit 1
      fi
      rm -rf "$OLD"
    else
      mv "$TMP" "$TARGET"
    fi
    trap - EXIT
    BIN="$TARGET/Contents/MacOS/Onyx"
    ARCHS="$(lipo -archs "$BIN")"
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TARGET/Contents/Info.plist")"
    echo "Installed Onyx $VERSION ($ARCHS) to $TARGET"
    if [ "${UNIVERSAL:-1}" = 1 ]; then
      case "$ARCHS" in *arm64*x86_64*|*x86_64*arm64*) ;; *) echo "warning: not universal ($ARCHS)" >&2 ;; esac
    elif [ -n "${ARCH:-}" ]; then
      case " $ARCHS " in
        *" $ARCH "*) ;;
        *) echo "warning: expected architecture $ARCH, got ($ARCHS)" >&2 ;;
      esac
    fi
    codesign --verify --deep "$TARGET" >/dev/null 2>&1 && echo "Code signature: valid" || echo "warning: code signature did not verify" >&2
    if [ "$WAS_RUNNING" = 1 ] && [ "${RELAUNCH:-0}" = 1 ]; then
      echo "Relaunching Onyx."
      open "$TARGET"
    fi
    ;;
  uninstall)
    [ -e "$TARGET" ] || { echo "Nothing to uninstall at $TARGET"; exit 0; }
    quit_onyx
    rm -rf "$TARGET"
    echo "Removed $TARGET"
    ;;
  *) echo "usage: $0 install|uninstall" >&2; exit 2 ;;
esac
