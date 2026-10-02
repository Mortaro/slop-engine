#!/bin/bash
# Replication by write, end to end: a gauge the server writes reaches the bot on every write, one it never writes
# arrives once. Run from anywhere: bash examples/replication_check/test.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
spite="${SPITE:-$here/../../../SpiteLanguage/bin/spite}"
out="$here/.test"
mkdir -p "$out"
for environment in server bot; do
    "$spite" "$here" --environment=$environment --build --executable-path="$out/$environment.exe" $SPITE_FLAGS
done
"$out/server.exe" --port=7273 --lifetime-seconds=60 > "$out/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
"$out/bot.exe" --port=7273
