#!/bin/sh
# `ui(<VStack>…)` against sui's own declarations: what compiles, and what does not.
#
#   ./tests/run_markup.sh
cd "$(dirname "$0")/.."
fails=0
# `-D mui_nodes`: these fixtures read the tree back as `nui.Node` props, and
# building this backend's own views is the default since 2026-09-27 -- on that
# route there are no props to read and a two-way control takes the cell, not a
# value. The views route has its own check beside this one.
common="-cp src -lib rui -lib nui -lib mui -D mui_backend=sui -D mui_nodes --macro sui.nui.Vocabulary.registerWithMui()"

haxe $common -cp tests/markup -main MarkupCheck --interp || fails=$((fails + 1))

out=$(haxe $common -cp tests/markup/refused -main BadAttr --interp --no-output 2>&1)
if echo "$out" | grep -q 'n.a pas d.attribut "onTogle"'; then
	echo "ok   a misspelt attribute is refused, and the message lists what is accepted"
else
	echo "FAIL onTogle was not refused:"; echo "$out"; fails=$((fails + 1))
fi

out=$(haxe $common -cp tests/markup/refused -main BadTag --interp --no-output 2>&1)
if echo "$out" | grep -q 'Hologramme'; then
	echo "ok   a tag nothing declares is refused by name"
else
	echo "FAIL Hologramme was not refused:"; echo "$out"; fails=$((fails + 1))
fi

echo ""
[ "$fails" -eq 0 ] && echo "all good" || echo "$fails failed"
exit "$fails"
