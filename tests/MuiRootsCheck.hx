import sui.runtime.ViewNodeBridge;

/**
	The real mui mapper, end to end: a mui application's declarations reach
	the bridge through the hooks `sui.mui.App`'s constructor installs. Pins
	what maps and — as deliberately — what does not: Preferences and every
	Auxiliary mount as roots; Glance never does (it is the snapshot corner,
	P4a, and a declaration must not mount because a mapper was careless).

	Compiled WITH the mui chain (Bind resolves the vocabulary), unlike its
	siblings — see run_dynamic.sh.
**/
class MuiRootsCheck {
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
		Sys.println("sui — mui declarations as roots");

		var app = new MuiRootsApp();
		ViewNodeBridge.setApp(app);

		ok(ViewNodeBridge.getRootFor("body") != null, "the Primary mounts");
		ok(ViewNodeBridge.getRootFor("prefs") != null, "the Preferences declaration mounts");
		ok(ViewNodeBridge.getRootFor("inspector") != null, "an Auxiliary declaration mounts");
		ok(ViewNodeBridge.getRootFor("gauges") != null, "…and so does the second one (cardinality Many)");
		ok(ViewNodeBridge.getRootFor("glance") == null,
			"a Glance declaration does NOT mount — the snapshot corner stays unmapped");

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

private class MuiRootsApp extends mui.App {
	override function body():mui.View return new sui.View();

	@:surface(Preferences)
	function prefs():mui.View return new sui.View();

	@:surface(Auxiliary)
	function inspector():mui.View return new sui.View();

	@:surface(Auxiliary)
	function gauges():mui.View return new sui.View();

	@:surface(Glance)
	function glance():mui.View return new sui.View();
}
