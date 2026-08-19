import sui.runtime.ViewNodeBridge;

/**
	The multi-root bridge, checked where it can lie: root registry, the
	every-root rebuild, and — the part that is structural, not stylistic —
	the SINGLE lifetime pass across all roots. The roots share the app's one
	`rui.Lifetime`, so a rebuild that skipped a root would sweep that root's
	`keep` keys; this pins that every root's keeps survive a full rebuild and
	that a key a root stops declaring is still swept.

	Plain Haxe, no Swift, no mui: the extra-roots hook is installed by hand,
	the way `sui.mui.App` installs it from declarations.

	  ./tests/run_dynamic.sh
**/
class MultiRootCheck {
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
		Sys.println("sui — multi-root bridge");

		var app = new MultiRootApp();
		ViewNodeBridge.extraRootsOf = function(_) {
			return [{id: "prefs", content: function() return app.prefs()}];
		};
		ViewNodeBridge.setApp(app);

		ok(ViewNodeBridge.getRoot() != null, "the Primary root exists");
		ok(ViewNodeBridge.getRootFor("body") == ViewNodeBridge.getRoot(),
			"getRootFor(\"body\") is the Primary");
		ok(ViewNodeBridge.getRootFor("prefs") != null, "the declared root is mounted");
		ok(ViewNodeBridge.getRootFor("absent") == null,
			"an undeclared id answers null — degradation, not an error");

		var body1 = ViewNodeBridge.getRoot();
		var prefs1 = ViewNodeBridge.getRootFor("prefs");
		ViewNodeBridge.rebuild();
		ok(ViewNodeBridge.getRoot() != body1 && ViewNodeBridge.getRootFor("prefs") != prefs1,
			"every root rebuilds together");
		ok(app.bodyKeeps == 1 && app.prefsKeeps == 1,
			"each root's keep survives the shared pass across rebuilds");

		app.declarePrefsKeep = false;
		ViewNodeBridge.rebuild();
		ok(app.prefsKeeps == 0, "a key a root stops declaring is swept");
		ok(app.bodyKeeps == 1, "…and the other root's key is untouched");

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

private class MultiRootApp extends sui.App {
	public var bodyKeeps = 0;
	public var prefsKeeps = 0;
	public var declarePrefsKeep = true;

	override function body():sui.View {
		lifetime.keep("body-res", function() {
			bodyKeeps++;
			return function() bodyKeeps--;
		});
		return new sui.View();
	}

	public function prefs():sui.View {
		if (declarePrefsKeep) lifetime.keep("prefs-res", function() {
			prefsKeeps++;
			return function() prefsKeeps--;
		});
		return new sui.View();
	}
}
