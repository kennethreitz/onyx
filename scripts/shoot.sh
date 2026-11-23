#!/bin/bash
# shoot.sh NAME [onyx args...] — launch Onyx against the test vault and capture its window.
set -e
NAME="$1"; shift
OUT="${SHOTS:-$HOME/repos/onyx/build/shots}"
mkdir -p "$OUT"
pkill -f "Onyx --vault .*--window-id-file /tmp/onyx-wid" 2>/dev/null || true; sleep 0.5
rm -f /tmp/onyx-wid
open -n --env ONYX_ALLOW_MULTIPLE=1 --env ONYX_NO_DEFAULT_VAULT=1 "$(dirname "$0")/../build/Onyx.app" --args --vault "${VAULT:-/tmp/onyx-vault}" --window-id-file /tmp/onyx-wid --size 1320x860 "$@"
sleep "${WAIT:-4}"
screencapture -x -o -l "$(cat /tmp/onyx-wid)" "$OUT/$NAME.png"
cp "$OUT/$NAME.png" "/tmp/onyx-$NAME.png"
echo "$OUT/$NAME.png"
