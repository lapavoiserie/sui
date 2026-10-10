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

# The controls declared for the desktop chores client: each one built by
# markup as sui's own class, carrying what the canon says it carries.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Controls --interp 2>&1)
expect() {
	if echo "$out" | grep -qF "$1"; then
		echo "ok   $2"
	else
		echo "FAIL $2 -- expected: $1"; echo "$out"; fails=$((fails + 1))
	fi
}
expect "section: Récurrence children=1" "a Section carries its title and its rows"
expect "divider" "a Divider is built"
expect "icon: mic label=Micro" "an Icon carries its name and its spoken label"
expect "menu: Actions items=sui.ui.Button,sui.ui.Divider,sui.ui.Button" "a Menu's items are ordinary buttons and dividers"
expect "picker: Période style=segmented options=4 sem.|Semaine|Mois" "a Picker carries the segmented hint"
expect "stepper: Toutes les bound=interval 1..999 step=1" "a Stepper binds its cell by name, with its bounds and a default step"
expect "date: Première échéance bound=due min=2026-01-01 max=null" "a DateInput binds a civil-day cell, with optional bounds"
expect "tabs: style=sidebar bound=section pages=0,1,0" "only the selected tab carries its page"
expect "sheet: Nouvelle tâche bound=editing children=0" "a sheet not presented carries no content"
expect "confirm: Archiver ? bound=archiving Archiver/Annuler destructive=true" "a ConfirmDialog carries both of the application's labels"
expect "confirm ran: true" "and its act is the closure markup gave it"
expect "structural: editing,section" "a selection and a presented flag are read as shape, so writing them rebuilds"
# A stack's alignment is the parent's business: a property, not a modifier.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Stacks --interp 2>&1)
if echo "$out" | grep -q "stacks: Leading Top Center"; then
	echo "ok   a stack takes its canonical alignment from markup, centre by default"
else
	echo "FAIL stack alignment:"; echo "$out"; fails=$((fails + 1))
fi

# A value makes a bar; a ProgressView without one is a spinner.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Progress --interp 2>&1)
if echo "$out" | grep -q "progress: 0.4 null"; then
	echo "ok   a ProgressView given a value is a bar, without one a spinner"
else
	echo "FAIL progress value:"; echo "$out"; fails=$((fails + 1))
fi

# `width` is honoured, so it must reach the renderer as a Frame it draws.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Frames --interp 2>&1)
if echo "$out" | grep -q "frame: Frame 70,null,null"; then
	echo "ok   a width from markup is a Frame with that width and no height"
else
	echo "FAIL width frame:"; echo "$out"; fails=$((fails + 1))
fi
# The colours: a role stays a role on the view and across the wire; a
# background keeps its radius, a border its width and radius.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Colours --interp 2>&1)
for want in "chain: ForegroundColor(Role(danger))" \
		"Fill(Role(surface),10) | Stroke(Role(border),1,10)" \
		"chain: ForegroundColor(Custom(#16319f))" \
		"described: backgroundColor=role:surface/10 | border=role:border/1,10"; do
	if echo "$out" | grep -qF "$want"; then
		echo "ok   colour: $want"
	else
		echo "FAIL colour: expected $want"; echo "$out"; fails=$((fails + 1))
	fi
done


# A button says how much it stands out; a check carries whether it is ticked.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Buttons --interp 2>&1)
if echo "$out" | grep -q "buttons: primary plain check/true null/false"; then
	echo "ok   a Button carries its style hint, and a check whether it is ticked"
else
	echo "FAIL button styles:"; echo "$out"; fails=$((fails + 1))
fi
if echo "$out" | grep -q "icon: refresh label=Actualiser"; then
	echo "ok   a Button takes its icon from markup, and keeps its label"
else
	echo "FAIL button icon:"; echo "$out"; fails=$((fails + 1))
fi

# A screen's commands are a Toolbar of ordinary controls.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-main Toolbars --interp 2>&1)
if echo "$out" | grep -q "toolbar: Aujourd'hui sui.ui.Button,sui.ui.Button"; then
	echo "ok   a Toolbar carries its title and ordinary controls"
else
	echo "FAIL toolbar:"; echo "$out"; fails=$((fails + 1))
fi

# A decoration this backend cannot draw is refused BY NAME while compiling.
# Skipping quietly is the canon's rule for a tree that arrived, not for markup
# somebody is writing against a backend they chose.
out=$(haxe $common --macro "sui.nui.Vocabulary.registerWithMui()" \
	-cp tests/markup-views/refused -main BadDecoration --interp 2>&1)
if echo "$out" | grep -q 'ne sait pas dessiner "flex"' \
		&& echo "$out" | grep -q "honore"; then
	echo "ok   a decoration it cannot draw is refused, and the message lists what it can"
else
	echo "FAIL flex was not refused clearly:"; echo "$out"; fails=$((fails + 1))
fi

echo ""
[ "$fails" -eq 0 ] && echo "all good" || echo "$fails failed"
exit "$fails"
