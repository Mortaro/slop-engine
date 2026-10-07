#!/bin/bash
# The systems of a stage run one after another in written order, so two runs must give exactly the same checksum.
cd "$(dirname "$0")/.."
spite="${SPITE:-D:/Projects/SpiteLanguage/bin/spite}"
first=$("$spite" parallel_check 2>&1 | grep "^alive")
echo "$first"
second=$("$spite" parallel_check 2>&1 | grep "^alive")
echo "$second"
passed=false
if [ -n "$first" ] && [ "$first" == "$second" ]; then
    passed=true
fi
echo "passed $passed"
[ "$passed" == "true" ]
