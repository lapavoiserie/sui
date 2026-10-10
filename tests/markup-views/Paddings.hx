import mui.macros.Markup.ui;

/** A padding by edges, from markup. See `check.sh`. **/
class Paddings {
	static function main() {
		var edges:sui.View = cast ui(<VStack padding={{top: 0.0, right: 4.0, left: 14.0}}><Text text="a"/></VStack>);
		var round:sui.View = cast ui(<VStack padding={8.0}><Text text="b"/></VStack>);
		Sys.println("edges: " + [for (m in edges.modifierChain) Std.string(m)].join(","));
		Sys.println("round: " + [for (m in round.modifierChain) Std.string(m)].join(","));
	}
}
