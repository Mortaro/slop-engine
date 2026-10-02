#!/bin/bash
# Parallel stages must give exactly what one thread gives: run serially once, then in parallel five times, and
# require every checksum to match.
cd "$(dirname "$0")/.."
spite="${SPITE:-D:/Projects/SpiteLanguage/bin/spite}"
serial=$("$spite" parallel_check --parallel=false 2>&1 | grep "^parallel")
echo "$serial"
passed=true
for run in 1 2 3 4 5; do
    parallel=$("$spite" parallel_check 2>&1 | grep "^parallel")
    echo "$parallel"
    if [ "${parallel#parallel true}" != "${serial#parallel false}" ] || [ -z "$serial" ]; then
        passed=false
    fi
done
echo "passed $passed"
[ "$passed" == "true" ]
