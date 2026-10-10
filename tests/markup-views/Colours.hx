import mui.macros.Markup.ui;

/** The canon's colours, written in markup, on sui's own views. See `check.sh`. **/
class Colours {
	static function main() {
		var late:sui.View = ui(<Text text="En retard" foregroundColor={nui.Color.role(Danger)}/>);
		var card:sui.View = ui(<VStack backgroundColor={{colour: nui.Color.role(Surface), radius: 10.0}}
			border={{colour: nui.Color.role(Border), width: 1.0, radius: 10.0}}><Text text="x"/></VStack>);
		var exact:sui.View = ui(<Text text="#" foregroundColor={nui.Color.rgb(22, 49, 159)}/>);
		for (v in [late, card, exact]) Sys.println("chain: " + [for (m in v.modifierChain) Std.string(m)].join(" | "));
		// And it crosses back as the canon said it: a role as a role.
		var node = sui.nui.Describe.describe(card);
		Sys.println("described: " + [for (m in node.modifiers) m.type + "=" + m.strings.join(",") + (m.floats == null ? "" : "/" + m.floats.join(","))].join(" | "));
	}
}
