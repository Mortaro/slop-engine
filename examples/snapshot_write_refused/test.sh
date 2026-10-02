#!/bin/bash
# An IO system that writes an inline component of its row must fail to compile, naming the line.
cd "$(dirname "$0")/.."
output=$(D:/Projects/SpiteLanguage/bin/spite snapshot_write_refused --check 2>&1)
if echo "$output" | grep -q "writes its parameter 'quitting' at .*quitter.spite:9"; then
    echo "refused at quitter.spite:9 passed true"
else
    echo "$output" | grep -v spite.assert | tail -5
    echo "passed false"
    exit 1
fi
