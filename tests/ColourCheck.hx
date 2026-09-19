/**
	What a colour says on the way out, and what Swift draws for one.

	`sui` described no colour modifier at all: it resolves colours in SwiftUI,
	which is right for drawing here and meant a panel projected from this
	machine arrived with nothing on it.
**/
class ColourCheck {
	static var failures = 0;

	static function check(what:String, ok:Bool, ?extra:Dynamic):Void {
		Sys.println((ok ? "ok   " : "FAIL ") + what + (ok || extra == null ? "" : " — " + extra));
		if (!ok) failures++;
	}

	static function said(v:sui.View):String {
		var n = sui.nui.Describe.describe(v);
		return n.modifiers.length == 0 ? "(rien)" : n.modifiers[0].strings[0];
	}

	static function main() {
		check("an accent crosses as a role",
			said(new sui.ui.Text("x").foregroundColor(Accent)) == "role:accent",
			said(new sui.ui.Text("x").foregroundColor(Accent)));
		check("a named colour leaves as components",
			said(new sui.ui.Text("x").foregroundColor(Gray)) == "#808080");
		check("and a custom hex as itself",
			said(new sui.ui.Text("x").foregroundColor(Custom("#C8323C"))) == "#c8323c");
		check("clear adds nothing at all",
			said(new sui.ui.Text("x").foregroundColor(Clear)) == "(rien)");

		// A role becomes a SEMANTIC colour, not a number: `.red` on Apple's
		// platforms shifts with the display and with increased contrast, and
		// the accent is the one the person chose.
		check("a role becomes a semantic colour in Swift",
			sui.nui.Colors.swift("role:accent") == "Color.accentColor"
			&& sui.nui.Colors.swift("role:danger") == "Color.red"
			&& sui.nui.Colors.swift("role:text") == "Color.primary",
			sui.nui.Colors.swift("role:accent"));
		check("and components become an sRGB colour",
			sui.nui.Colors.swift("#c8323c") == "Color(.sRGB, red: 0.78, green: 0.2, blue: 0.24, opacity: 1)",
			sui.nui.Colors.swift("#c8323c"));
		check("a malformed colour draws nothing rather than a guess",
			sui.nui.Colors.swift("#ggg") == null && sui.nui.Colors.swift("red") == null);

		Sys.println(failures == 0 ? "\nall checks passed" : '\n$failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}
