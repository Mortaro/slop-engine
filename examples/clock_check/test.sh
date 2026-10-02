#!/bin/bash
# The server owns the game clock: a bot following it sees a mirrored timer ring at the same game time as the server
# does, though the server started its clock 1,000 seconds ahead. Run from anywhere: bash examples/clock_check/test.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
spite="${SPITE:-$here/../../../SpiteLanguage/bin/spite}"
out="$here/.test"
mkdir -p "$out"
for environment in server bot; do
    "$spite" "$here" --environment=$environment --executable --run=false --executable-path="$out/$environment.exe" $SPITE_FLAGS
done
"$out/server.exe" --port=7277 --lifetime-seconds=60 > "$out/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
"$out/bot.exe" --port=7277
