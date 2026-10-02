#!/bin/bash
# Server-authoritative click counter, end to end: a server and three headless bots in separate processes.
# Run from anywhere: bash examples/click_counter_online/test.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
spite="${SPITE:-$here/../../../SpiteLanguage/bin/spite}"
out="$here/.test"
mkdir -p "$out"
for environment in server bot; do
    "$spite" "$here" --environment=$environment --executable --run=false --executable-path="$out/$environment.exe" $SPITE_FLAGS
done

"$out/server.exe" --port=7171 --lifetime-seconds=60 > "$out/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT

expect_line() {
    local got
    got="$("$out/bot.exe" --port=7171 --clicks=$1 --expect=$2 | tail -1)"
    echo "$got"
    [ "$got" = "$3" ] || { echo "FAILED: expected '$3'"; exit 1; }
}

expect_line 3 0 "bot clicked 3 and sees 3"
expect_line 0 3 "bot clicked 0 and sees 3"
expect_line 2 3 "bot clicked 2 and sees 5"
echo "passed true"
