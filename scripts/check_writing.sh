#!/bin/bash
# No em dashes anywhere, neither the character nor two hyphens between spaces standing in for one, and no game built
# on the engine named inside it (CLAUDE.md, "Writing"). Every tracked text file is read, and with --staged the
# staged version of every file about to be committed. Third-party license texts are quoted as written.
# A '--' between spaces is allowed only where it is a command line's own separator: before a flag, or after
# 'spite <program>'.

cd "$(dirname "$0")/.." || exit 1

em_dash=$(printf '\342\200\224')
stand_in=' -''- '   # written in two pieces so this file does not contain what it refuses
names='thes''eus'   # the same, for the name it refuses
exempt=(':!*OFL.txt' ':!*LICENSE*')

if [ "$1" = "--staged" ]; then
    search=(git grep --cached -n -I)
else
    search=(git grep -n -I)
fi

failed=0
dashes=$("${search[@]}" -F -e "$em_dash" -e "$stand_in" . "${exempt[@]}" \
    | grep -v -E "$stand_in-|(spite|bin/spite|spite\.exe) [^ ]+$stand_in")
if [ -n "$dashes" ]; then
    echo "em dashes (end the sentence, or use a colon, a comma or parentheses):"
    echo "$dashes"
    failed=1
fi
games=$("${search[@]}" -i -E -e "$names" . "${exempt[@]}")
if [ -n "$games" ]; then
    echo "a game built on the engine is named (write \"a game\"):"
    echo "$games"
    failed=1
fi
exit $failed
