#!/bin/bash
# Area of interest, end to end: a server with 100 beacons and a bot whose view follows a moving eye.
# Run from anywhere: bash examples/interest_check/test.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
spite="$here/../../../SpiteLanguage/bin/spite"
out="$here/.test"
mkdir -p "$out"
for environment in server bot; do
    "$spite" "$here" --environment=$environment --executable --run=false --executable-path="$out/$environment.exe"
done
"$out/server.exe" --port=7272 --lifetime_seconds=60 > "$out/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
"$out/bot.exe" --port=7272
