#!/bin/bash
# Compile the Onyx release binary. Native by default; UNIVERSAL=1 builds arm64 + x86_64.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CONFIG="${1:-release}"
UNIVERSAL="${UNIVERSAL:-0}"
ARCH="${ARCH:-}"

is_universal() {
  local info
  info=$(lipo -info "$1" 2>/dev/null) || return 1
  echo "$info" | grep -q arm64 || return 1
  echo "$info" | grep -q x86_64 || return 1
}

# SwiftPM 6 / swiftbuild uses .build/<config> as a symlink to out/Products/<Config>.
find_product() {
  local scratch="$1"
  local show
  show=$(swift build -c "$CONFIG" --scratch-path "$scratch" --show-bin-path 2>/dev/null || true)
  if [ -n "$show" ] && [ -x "$show/Onyx" ]; then
    echo "$show/Onyx"
    return
  fi
  local cap
  cap="$(printf '%s' "$CONFIG" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
  local c
  for c in \
    "$scratch/$CONFIG/Onyx" \
    "$scratch/out/Products/$cap/Onyx" \
    "$scratch/out/Products/$CONFIG/Onyx"
  do
    if [ -x "$c" ]; then echo "$c"; return; fi
  done
  return 1
}

if [ "$UNIVERSAL" != 1 ]; then
  if [ -n "$ARCH" ]; then
    case "$ARCH" in
      arm64|x86_64) ;;
      *) echo "error: ARCH must be arm64 or x86_64 (got '$ARCH')" >&2; exit 1 ;;
    esac
    echo "Building $CONFIG for ${ARCH}..."
    swift build -c "$CONFIG" --arch "$ARCH"
  else
    swift build -c "$CONFIG"
  fi
  exit 0
fi

echo "Building universal (arm64 + x86_64)…"
DEST="$ROOT/.build/universal/Onyx"
mkdir -p "$ROOT/.build/universal"

# Prefer one SwiftPM invocation when it actually emits a fat binary.
if swift build -c "$CONFIG" --arch arm64 --arch x86_64; then
  if BIN=$(find_product "$ROOT/.build") && is_universal "$BIN"; then
    cp "$BIN" "$DEST"
    chmod +x "$DEST"
    echo "SwiftPM wrote a universal binary"
    lipo -info "$DEST"
    file "$DEST"
    exit 0
  fi
  echo "SwiftPM did not emit a fat binary; building each architecture and lipo-ing…"
fi

ARM_SCRATCH="$ROOT/.build/scratch-arm64"
INTEL_SCRATCH="$ROOT/.build/scratch-x86_64"
swift build -c "$CONFIG" --arch arm64 --scratch-path "$ARM_SCRATCH"
swift build -c "$CONFIG" --arch x86_64 --scratch-path "$INTEL_SCRATCH"

ARM=$(find_product "$ARM_SCRATCH") || { echo "error: missing arm64 slice under $ARM_SCRATCH" >&2; exit 1; }
INTEL=$(find_product "$INTEL_SCRATCH") || { echo "error: missing x86_64 slice under $INTEL_SCRATCH" >&2; exit 1; }

lipo -create "$ARM" "$INTEL" -output "$DEST"
chmod +x "$DEST"
echo "Created $DEST from:"
echo "  arm64:  $ARM"
echo "  x86_64: $INTEL"
lipo -info "$DEST"
file "$DEST"
