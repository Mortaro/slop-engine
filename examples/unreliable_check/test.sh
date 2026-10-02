#!/bin/bash
# Unreliable delivery, end to end: a drift written every tick travels by datagram, settles by TCP once it stops even
# when datagrams are dropped, and a stale datagram is ignored. Run from anywhere: bash examples/unreliable_check/test.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
spite="${SPITE:-$here/../../../SpiteLanguage/bin/spite}"
out="$here/.test"
mkdir -p "$out"
for environment in server bot; do
    "$spite" "$here" --environment=$environment --executable --run=false --executable-path="$out/$environment.exe" $SPITE_FLAGS
done
"$out/server.exe" --port=7276 --lifetime-seconds=60 > "$out/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
"$out/bot.exe" --port=7276
