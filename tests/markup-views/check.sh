#!/usr/bin/env bash
#
# Markup builds sui's OWN controls, not a node.
#
#   ./tests/markup-views/check.sh
#
# This backend reads a received tree natively and never copies one into views,
# so markup that produced a node could not reach it except by going out over a
# wire and coming back.
#
# Its two-way controls are also the one shape in the family that holds a NAME
# rather than a cell: their state lives on the Swift side behind a registry.
# So markup carries the CELL -- `<Toggle isOn={lit_}/>`, no callback, because
# writes go home through the Swift binding -- and `Describe.nameOf` turns it
# into the name the control takes. That is checked here too: a control bound to
# the wrong name is a control bound to nothing.

set -u
cd "$(dirname "$0")/../.."
common="-cp src -cp tests/markup-views -lib rui -lib nui -lib mui -D mui_backend=sui"
fails=0

out=$(haxe $common -D mui_views --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main SuiMarkup --interp 2>&1)
if echo "$out" | grep -q "built: sui.ui.VStack"; then
	echo "ok   markup builds sui's own controls"
else
	echo "FAIL markup did not build sui's own controls:"; echo "$out"; fails=$((fails + 1))
fi
if echo "$out" | grep -q "toggle bound to: lit"; then
	echo "ok   and the control holds the cell's name, which is what it binds by"
else
	echo "FAIL the toggle is not bound to the cell:"; echo "$out"; fails=$((fails + 1))
fi

# Without the flag the same source does not even mean the same thing: the node
# path wants a Bool where the view path wants the cell. Asserted rather than
# assumed -- a check that passed either way would say nothing.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main SuiMarkup --interp 2>&1)
if echo "$out" | grep -q "should be Bool"; then
	echo "ok   and without -D mui_views the node path wants a value, not a cell"
else
	echo "FAIL the flag made no difference:"; echo "$out"; fails=$((fails + 1))
fi

echo ""
[ "$fails" -eq 0 ] && echo "all good" || echo "$fails failed"
exit "$fails"
