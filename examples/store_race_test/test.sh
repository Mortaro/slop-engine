#!/bin/bash
# Four processes write to one store at once; every record must read back as itself.
cd "$(dirname "$0")/.."
spite=D:/Projects/SpiteLanguage/bin/spite
out="$(pwd)/store_race_test/.test"
rm -rf "$out"; mkdir -p "$out"
"$spite" store_race_test --executable --run=false --executable-path="$out/race.exe" || exit 1
for writer in 0 1 2 3; do
    "$out/race.exe" --role=write --writer=$writer --store-path="$out/store.bin" &
done
wait
"$out/race.exe" --role=check --store-path="$out/store.bin"
