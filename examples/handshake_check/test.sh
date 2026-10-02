#!/bin/bash
# The connection handshake: a build whose replicated components differ is refused by both sides before anything is
# read, the server keeps serving a matching build, and two components hashing to one message id crash at startup.
# Run from anywhere: bash examples/handshake_check/test.sh
set -e
here="$(cd "$(dirname "$0")" && pwd)"
spite="${SPITE:-$here/../../../SpiteLanguage/bin/spite}"
out="$here/.test"
mkdir -p "$out"
for environment in server bot stranger clash; do
    "$spite" "$here" --environment=$environment --build --executable-path="$out/$environment.exe" $SPITE_FLAGS
done
"$out/server.exe" --port=7275 --lifetime-seconds=60 > "$out/server.log" 2>&1 &
server=$!
trap 'kill $server 2>/dev/null || true' EXIT
"$out/stranger.exe" --port=7275
"$out/bot.exe" --port=7275
# The server refuses on its own tick: wait for its line, or for it to exit without one.
while ! grep -q "refusing connection" "$out/server.log"; do
    kill -0 $server 2>/dev/null || { echo "FAILED: the server did not refuse the stranger"; exit 1; }
    sleep 0.2
done
echo "server refused the stranger too"
clash=$("$out/clash.exe" 2>&1 || true)
if ! echo "$clash" | grep -q "no_two_replicated_components_share_a_message_id"; then
    echo "$clash" | tail -5
    echo "FAILED: two components with one message id did not crash"
    exit 1
fi
echo "$clash" | grep "hash to the same message id"
echo "passed true"
