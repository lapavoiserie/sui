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

out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main SuiMarkup --interp 2>&1)
if echo "$out" | grep -q "built: sui.ui.VStack"; then
	echo "ok   markup builds sui's own controls"
else
	echo "FAIL markup did not build sui's own controls:"; echo "$out"; fails=$((fails + 1))
fi
if echo "$out" | grep -q "keys: a,b"; then
	echo "ok   a key written in markup reaches the view"
else
	echo "FAIL a written key did not reach the view:"; echo "$out"; fails=$((fails + 1))
fi

if echo "$out" | grep -q "toggle bound to: lit"; then
	echo "ok   and the control holds the cell's name, which is what it binds by"
else
	echo "FAIL the toggle is not bound to the cell:"; echo "$out"; fails=$((fails + 1))
fi

# `-D mui_nodes` is the way back, and the same source does not even mean the
# same thing there: the node path wants a Bool where the view path wants the
# cell. Asserted rather than assumed -- a check that passed either way would
# say nothing, and this one is what proves the default really changed.
out=$(haxe $common -D mui_nodes --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main SuiMarkup --interp 2>&1)
if echo "$out" | grep -q "should be Bool"; then
	echo "ok   and with -D mui_nodes the node path wants a value, not a cell"
else
	echo "FAIL the flag made no difference:"; echo "$out"; fails=$((fails + 1))
fi

# A decoration this backend cannot draw is refused BY NAME while compiling.
# Skipping quietly is the canon's rule for a tree that arrived, not for markup
# somebody is writing against a backend they chose.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-cp tests/markup-views/refused -main BadDecoration --interp 2>&1)
if echo "$out" | grep -q 'ne sait pas dessiner "backgroundColor"' \
		&& echo "$out" | grep -q "honore"; then
	echo "ok   a decoration it cannot draw is refused, and the message lists what it can"
else
	echo "FAIL backgroundColor was not refused clearly:"; echo "$out"; fails=$((fails + 1))
fi

echo ""
[ "$fails" -eq 0 ] && echo "all good" || echo "$fails failed"
exit "$fails"
