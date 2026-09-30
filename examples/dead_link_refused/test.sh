#!/bin/bash
# A link component is added only once its entity is set and alive: adding one naming a despawned entity, or one
# left at its unset default, must crash naming the rule.
here="$(cd "$(dirname "$0")" && pwd)"
out="$here/.test"
mkdir -p "$out"
"$here/../../../SpiteLanguage/bin/spite" "$here" --executable --run=false --executable-path="$out/refused.exe" || exit 1
passed=true
dead=$("$out/refused.exe" --link=dead 2>&1)
if ! echo "$dead" | grep -q "a_link_names_a_living_entity"; then
    echo "$dead" | tail -5
    passed=false
fi
unset=$("$out/refused.exe" --link=unset 2>&1)
if ! echo "$unset" | grep -q "a_link_is_added_only_once_its_entity_is_set"; then
    echo "$unset" | tail -5
    passed=false
fi
echo "dead and unset links crashed passed $passed"
[ "$passed" = true ]
