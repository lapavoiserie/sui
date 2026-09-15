import nui.Node;
import nui.PropValue;
import sui.runtime.ViewNodeBridge;

/**
	A tree that arrived, read through the same C-facing accessors
	`DynamicView.swift` calls — in `sui`'s spelling, answered from canonical
	nodes — and edits on received controls running the actions they carry.

	    haxe -cp src -cp tests -lib rui -lib nui --interp -main ReceivedCheck
**/
class ReceivedCheck {
	static var fails = 0;

	static function check(label:String, ok:Bool, ?got:Dynamic) {
		if (!ok) fails++;
		Sys.println((ok ? "  ok   " : "  FAIL ") + label + (ok || got == null ? "" : '  (got: $got)'));
	}

	static function main() {
		Sys.println("sui — drawing a received tree");

		var typed:Array<String> = [];
		var toggled:Array<Bool> = [];
		var slid:Array<Float> = [];
		var clicks = 0;

		function tree(title:String):Node {
			var root = new Node("VStack").prop("spacing", PInt(8));
			root.child(new Node("Text").prop("text", PString(title))
				.modifier({type: "padding", floats: [12]})
				.modifier({type: "foregroundColor", strings: ["Red"]})
				.modifier({type: "padding"}));
			root.child(new Node("Button").prop("label", PString("Add")).prop("onClick", PCallback(() -> clicks++)));
			root.child(new Node("Toggle").prop("label", PString("Lamp")).prop("isOn", PBool(true))
				.prop("onToggle", PCallbackBool(v -> toggled.push(v))));
			root.child(new Node("TextInput").prop("text", PString("hello")).prop("placeholder", PString("Name"))
				.prop("onText", PCallbackString(s -> typed.push(s))));
			root.child(new Node("Slider").prop("value", PFloat(2.5)).prop("min", PFloat(0)).prop("max", PFloat(10))
				.prop("onValue", PCallbackFloat(f -> slid.push(f))));
			root.child(new Node("ProgressView").prop("value", PFloat(0.25)));
			root.child(new Node("LevelMeter").prop("stream", PString("vu.master")).prop("floorDb", PFloat(-60.0)).prop("channels", PInt(2)));
			return root;
		}

		var current = tree("first");
		check("nothing received yet: not reading", !ViewNodeBridge.reading());
		ViewNodeBridge.readThrough(new nui.SelfSource(() -> current));
		check("reading once a source is installed", ViewNodeBridge.reading());

		var root = ViewNodeBridge.getRoot();
		check("the root is the received tree", ViewNodeBridge.getViewType(root) == "VStack", ViewNodeBridge.getViewType(root));
		check("the Primary by id is it too", ViewNodeBridge.getRootFor("body") == root);
		check("its children are counted", ViewNodeBridge.getChildCount(root) == 7, ViewNodeBridge.getChildCount(root));
		check("a number crosses as the text the renderer parses", ViewNodeBridge.getStringProperty(root, "spacing") == "8",
			ViewNodeBridge.getStringProperty(root, "spacing"));

		var text = ViewNodeBridge.getChild(root, 0);
		check("Text: its text", ViewNodeBridge.getTextContent(text) == "first", ViewNodeBridge.getTextContent(text));
		check("modifiers: padding with a value is Padding", ViewNodeBridge.getModifierType(text, 0) == "Padding"
			&& ViewNodeBridge.getModifierFloat(text, 0, 0) == 12);
		check("foregroundColor is ForegroundColor, its colour kept", ViewNodeBridge.getModifierType(text, 1) == "ForegroundColor"
			&& ViewNodeBridge.getModifierString(text, 1, 0) == "Red");
		check("padding without a value is PaddingDefault", ViewNodeBridge.getModifierType(text, 2) == "PaddingDefault",
			ViewNodeBridge.getModifierType(text, 2));
		check("a received node displays no cell here", ViewNodeBridge.getValueDependencies(text) == "");

		var button = ViewNodeBridge.getChild(root, 1);
		check("Button: its label", ViewNodeBridge.getButtonLabel(button) == "Add");
		ViewNodeBridge.invokeButtonAction(button);
		check("a tap runs the closure it carries", clicks == 1, clicks);

		var toggle = ViewNodeBridge.getChild(root, 2);
		check("Toggle: isOn is the value a checkbox reads", ViewNodeBridge.getStringProperty(toggle, "value") == "true");
		check("and has no cell binding to be mistaken for", ViewNodeBridge.getStringProperty(toggle, "isOnBinding") == "");
		var togglePath = ViewNodeBridge.getStringProperty(toggle, "path");
		check("its edits have a path", StringTools.startsWith(togglePath, "nui:"), togglePath);
		ViewNodeBridge.setData(togglePath, "false");
		check("an edit written there runs onToggle with the new value", toggled.join(",") == "false", toggled.join(","));

		var field = ViewNodeBridge.getChild(root, 3);
		check("TextInput is drawn as a TextField", ViewNodeBridge.getViewType(field) == "TextField", ViewNodeBridge.getViewType(field));
		check("its text is the value, its placeholder the label", ViewNodeBridge.getStringProperty(field, "value") == "hello"
			&& ViewNodeBridge.getStringProperty(field, "label") == "Name");
		var fieldPath = ViewNodeBridge.getStringProperty(field, "path");
		ViewNodeBridge.setData(fieldPath, "hello!");
		check("typing runs onText with the text", typed.join(",") == "hello!", typed.join(","));

		var slider = ViewNodeBridge.getChild(root, 4);
		check("Slider: value, min and max as text", ViewNodeBridge.getStringProperty(slider, "value") == "2.5"
			&& ViewNodeBridge.getStringProperty(slider, "min") == "0" && ViewNodeBridge.getStringProperty(slider, "max") == "10");
		ViewNodeBridge.setData(ViewNodeBridge.getStringProperty(slider, "path"), "4.5");
		check("sliding runs onValue with the number", slid.join(",") == "4.5", slid.join(","));

		var progress = ViewNodeBridge.getChild(root, 5);
		check("ProgressView carries its fraction", ViewNodeBridge.getStringProperty(progress, "value") == "0.25");
		check("a control without an action has no path", ViewNodeBridge.getStringProperty(progress, "path") == "");

		var meter = ViewNodeBridge.getChild(root, 6);
		check("a component's type passes through, for its registry", ViewNodeBridge.getViewType(meter) == "LevelMeter");
		check("and its props read as its own view reads them", ViewNodeBridge.getStringProperty(meter, "stream") == "vu.master"
			&& Std.parseFloat(ViewNodeBridge.getStringProperty(meter, "floorDb")) == -60
			&& ViewNodeBridge.getStringProperty(meter, "channels") == "2");

		var before = clicks;
		ViewNodeBridge.setData("some.app.path", "x");
		check("a path that is not ours is left to the application", clicks == before && typed.length == 1);

		// --- a new tree arrives ---
		current = tree("second");
		check("any write rebuilds while a tree is received", ViewNodeBridge.isStructural("status"));
		ViewNodeBridge.rebuild();
		var again = ViewNodeBridge.getRoot();
		check("a rebuild reads the new tree", ViewNodeBridge.getTextContent(ViewNodeBridge.getChild(again, 0)) == "second");
		var path2 = ViewNodeBridge.getStringProperty(ViewNodeBridge.getChild(again, 3), "path");
		check("a control keeps its path across generations", path2 == fieldPath, path2);

		// --- the application's own views still answer as themselves ---
		var own:sui.View = new sui.ui.Text("mine");
		check("a sui view is not taken for a received node", ViewNodeBridge.getViewType(own) == "Text"
			&& ViewNodeBridge.getTextContent(own) == "mine");

		ViewNodeBridge.readThrough(null);
		check("null hands the screen back", !ViewNodeBridge.reading() && ViewNodeBridge.getRoot() != again);

		Sys.println(fails == 0 ? "\nall good" : '\n$fails failed');
		Sys.exit(fails == 0 ? 0 : 1);
	}
}
