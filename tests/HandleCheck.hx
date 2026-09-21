import sui.runtime.ViewNodeBridge;

/**
	What a node handle resolves to after the tree changed under it.

	The renderer holds handles inside closures SwiftUI keeps across rebuilds,
	so a handle is read long after the tree it came from is gone. Three cases,
	and the third is the one that matters:

	- nothing moved: the handle reaches the same control in the NEW tree;
	- the control is still there with a sibling added AFTER it: same;
	- a component was inserted BEFORE it: the place now names something else,
	  and the handle must answer null -- an old slider's `set` resolving to
	  the toggle that took its place would write "0.37" into a Bool cell.

	  ./tests/run_dynamic.sh
**/
class HandleCheck {
	static var failures = 0;

	static function ok(cond:Bool, label:String):Void {
		if (cond) Sys.println("  ok   " + label);
		else { failures++; Sys.println("  FAIL " + label); }
	}

	static function main() {
		Sys.println("sui — node handles across rebuilds");

		var app = new HandleApp();
		ViewNodeBridge.setApp(app);

		var root = ViewNodeBridge.handleOfRoot("body", ViewNodeBridge.getRoot());
		function child(index:Int):Int
			return ViewNodeBridge.handleOfChild(root, index,
				ViewNodeBridge.getChild(ViewNodeBridge.nodeOf(root), index));

		// [Text, Slider]
		var slider = child(1);
		var signature = ViewNodeBridge.signatureOfPlace(slider);
		ok(ViewNodeBridge.getViewType(ViewNodeBridge.nodeOfChecked(slider, signature)) == "Slider",
			"a handle reaches the control it was issued for");

		var before = ViewNodeBridge.nodeOf(slider);
		ViewNodeBridge.rebuild();
		var after = ViewNodeBridge.nodeOfChecked(slider, signature);
		ok(after != null && after != before && ViewNodeBridge.getViewType(after) == "Slider",
			"after a rebuild it reaches the same control in the NEW tree");

		app.appended = true;
		ViewNodeBridge.rebuild();
		ok(ViewNodeBridge.nodeOfChecked(slider, signature) != null,
			"a sibling added after it changes nothing");

		// [Toggle, Text, Slider] -- index 1 is now the Text, index 2 the Slider.
		app.inserted = true;
		ViewNodeBridge.rebuild();
		ok(ViewNodeBridge.nodeOfChecked(slider, signature) == null,
			"a component inserted BEFORE it: the stale handle answers null, not the wrong control");

		// And the case a type check alone would miss: two sliders, two cells.
		app.inserted = false;
		app.twoSliders = true;
		ViewNodeBridge.rebuild();
		var level = child(1);
		var levelSignature = ViewNodeBridge.signatureOfPlace(level);
		app.swapped = true;
		ViewNodeBridge.rebuild();
		ok(ViewNodeBridge.nodeOfChecked(level, levelSignature) == null,
			"same type, different cell: still null -- for a control, identity is the cell");

		Sys.println("");
		Sys.println(failures == 0 ? "all good" : failures + " failed");
		if (failures > 0) Sys.exit(1);
	}
}

private class HandleApp extends sui.App {
	public var appended = false;
	public var inserted = false;
	public var twoSliders = false;
	public var swapped = false;

	override function body():sui.View {
		var rows:Array<sui.View> = [new sui.ui.Text("title")];
		if (twoSliders) {
			rows.push(new sui.ui.Slider(swapped ? "volume" : "level", 0, 1));
			rows.push(new sui.ui.Slider(swapped ? "level" : "volume", 0, 1));
		} else {
			rows.push(new sui.ui.Slider("level", 0, 1));
		}
		if (inserted) rows.unshift(new sui.ui.Toggle("lit", "lit"));
		if (appended) rows.push(new sui.ui.Text("footer"));
		return new sui.ui.VStack(rows);
	}
}
