import sui.runtime.ViewNodeBridge;

/**
	The command-set half of the bridge, checked where it can lie: the index
	enumeration C reaches (counts, labels, "" for a missing shortcut), the
	invoke-by-index round trip, the bounds guards (a menu held open across a
	rebuild may name an index the new sample no longer has), and — the part
	that keeps a menu honest — resampling with the roots on rebuild, plus the
	sampled reads counting as structural.

	Plain Haxe, no Swift, no mui: the hook is installed by hand, the way
	`sui.mui.App` installs it from declarations.

	  ./tests/run_dynamic.sh
**/
class CommandSetCheck {
	static var failures = 0;

	static function ok(cond:Bool, label:String):Void {
		if (cond) {
			Sys.println("  ok   " + label);
		} else {
			failures++;
			Sys.println("  FAIL " + label);
		}
	}

	static function main() {
		Sys.println("sui — command sets");

		var app = new CommandApp();
		ViewNodeBridge.commandSetsOf = function(_) {
			return [
				{id: "shortcuts", commands: function():Array<sui.runtime.ViewNodeBridge.CommandEntry> {
					app.sampled++;
					return [
						{label: "New " + app.noun, shortcut: "ctrl+n", action: function() app.created++},
						{label: "About", shortcut: null, action: function() app.abouted++},
					];
				}},
				{id: "extra", commands: function():Array<sui.runtime.ViewNodeBridge.CommandEntry> {
					return [{label: "Only", shortcut: "alt+shift+x", action: function() {}}];
				}},
			];
		};
		ViewNodeBridge.extraRootsOf = null;
		ViewNodeBridge.setApp(app);

		ok(ViewNodeBridge.commandSetCount() == 2, "both sets are registered");
		ok(ViewNodeBridge.commandSetId(0) == "shortcuts" && ViewNodeBridge.commandSetId(1) == "extra",
			"set ids answer in declaration order");
		ok(ViewNodeBridge.commandCount(0) == 2 && ViewNodeBridge.commandCount(1) == 1,
			"command counts per set");
		ok(ViewNodeBridge.commandLabel(0, 0) == "New todo", "labels come from the sample");
		ok(ViewNodeBridge.commandShortcut(0, 0) == "ctrl+n", "a chord crosses as its string");
		ok(ViewNodeBridge.commandShortcut(0, 1) == "", "no shortcut answers the empty string");

		ViewNodeBridge.invokeCommand(0, 0);
		ViewNodeBridge.invokeCommand(0, 1);
		ok(app.created == 1 && app.abouted == 1, "invoke-by-index runs the right action");

		// Out of range: ""/0/no-op, never a crash — a stale open menu is data.
		ViewNodeBridge.invokeCommand(5, 0);
		ViewNodeBridge.invokeCommand(0, 9);
		ok(ViewNodeBridge.commandLabel(5, 0) == "" && ViewNodeBridge.commandCount(5) == 0
			&& ViewNodeBridge.commandShortcut(0, 9) == "",
			"out-of-range indices degrade to empty answers");

		var sampledBefore = app.sampled;
		app.noun = "note";
		ViewNodeBridge.rebuild();
		ok(app.sampled == sampledBefore + 1, "rebuild resamples the sets with the roots");
		ok(ViewNodeBridge.commandLabel(0, 0) == "New note", "the menu's data follows the sample");

		if (failures == 0) {
			Sys.println("");
			Sys.println("all good");
		} else {
			Sys.println("");
			Sys.println(failures + " failed");
			Sys.exit(1);
		}
	}
}

private class CommandApp extends sui.App {
	public var noun = "todo";
	public var sampled = 0;
	public var created = 0;
	public var abouted = 0;

	override function body():sui.View {
		return new sui.View();
	}
}
