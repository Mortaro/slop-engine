#!/bin/bash
# Looking up a negative entity id must crash loudly, naming the rule, not read out of bounds or answer false.
cd "$(dirname "$0")/.."
output=$(D:/Projects/SpiteLanguage/bin/spite negative_lookup_refused 2>&1)
if echo "$output" | grep -q "looked_up_a_real_entity_not_a_negative_id"; then
    echo "negative lookup crashed passed true"
else
    echo "$output" | tail -5
    echo "passed false"
    exit 1
fi
