#!/bin/bash
# A component holding a List, a Dictionary or a Parallel must fail to compile, naming the rule and the component.
cd "$(dirname "$0")/.."
output=$(D:/Projects/SpiteLanguage/bin/spite list_component_refused --run=false 2>&1)
list=$(echo "$output" | grep -c "a_component_holds_no_list.*\|AttributeRule<Bag, List<Integer>>")
dictionary=$(echo "$output" | grep -c "AttributeRule<Table, Dictionary<Integer>>")
parallel=$(echo "$output" | grep -c "AttributeRule<Job, Parallel>")
if [ "$list" -gt 0 ] && [ "$dictionary" -gt 0 ] && [ "$parallel" -gt 0 ]; then
    echo "list, dictionary and parallel refused passed true"
else
    echo "$output" | grep -v spite.assert | tail -5
    echo "passed false"
    exit 1
fi
