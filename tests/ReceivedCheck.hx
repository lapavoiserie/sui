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
		var picked:Array<String> = [];

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
			root.child(new Node("Picker").prop("label", PString("Transition")).prop("selectedIndex", PInt(1))
				.prop("onSelect", PCallbackString(s -> picked.push(s)))
				.child(new Node("Text").prop("text", PString("Cut")))
				.child(new Node("Text").prop("text", PString("Fade"))));
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
		check("its children are counted", ViewNodeBridge.getChildCount(root) == 8, ViewNodeBridge.getChildCount(root));
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

		var picker = ViewNodeBridge.getChild(root, 6);
		check("Picker: drawn as a picker, selecting by position", ViewNodeBridge.getViewType(picker) == "Picker"
			&& ViewNodeBridge.getStringProperty(picker, "selectionMode") == "index");
		check("its value is the selected index, its label the label", ViewNodeBridge.getStringProperty(picker, "value") == "1"
			&& ViewNodeBridge.getStringProperty(picker, "label") == "Transition");
		check("its options are Text children", ViewNodeBridge.getChildCount(picker) == 2
			&& ViewNodeBridge.getTextContent(ViewNodeBridge.getChild(picker, 1)) == "Fade");
		ViewNodeBridge.setData(ViewNodeBridge.getStringProperty(picker, "path"), "0");
		check("choosing runs onSelect with the position, as the string an inflated action takes", picked.join(",") == "0", picked.join(","));

		var meter = ViewNodeBridge.getChild(root, 7);
		check("a component's type passes through, for its registry", ViewNodeBridge.getViewType(meter) == "LevelMeter");
		check("and its props read as its own view reads them", ViewNodeBridge.getStringProperty(meter, "stream") == "vu.master"
			&& Std.parseFloat(ViewNodeBridge.getStringProperty(meter, "floorDb")) == -60
			&& ViewNodeBridge.getStringProperty(meter, "channels") == "2");

		var before = clicks;
		ViewNodeBridge.setData("some.app.path", "x");
		check("a path that is not ours is left to the application", clicks == before && typed.length == 1);

		// --- pictures in a received tree ---
		//
		// Judged where trees arrive, by dui.nui.Reception, which turns a source a
		// received tree may not use into `refused:<reason>`; the renderer loads
		// nothing it does not know and draws the alt. The bridge passes sources on.
		var pictures = new Node("VStack")
			.child(new Node("Image").prop("src", PString("refused:a received tree may not name a local file")).prop("alt", PString("hosts")))
			.child(new Node("Image").prop("src", PString("data:image/png;base64,iVBORw0KGgo=")).prop("alt", PString("dot")))
			.child(new Node("Icon").prop("name", PString("mic-off")).prop("label", PString("Muted")));
		var previous = current;
		current = pictures;
		ViewNodeBridge.rebuild();
		var shown = ViewNodeBridge.getRoot();
		check("a refused source reaches the renderer as sent, with its alt",
			StringTools.startsWith(ViewNodeBridge.getStringProperty(ViewNodeBridge.getChild(shown, 0), "src"), "refused:")
			&& ViewNodeBridge.getStringProperty(ViewNodeBridge.getChild(shown, 0), "alt") == "hosts");
		check("a data: picture passes",
			StringTools.startsWith(ViewNodeBridge.getStringProperty(ViewNodeBridge.getChild(shown, 1), "src"), "data:image/png"));
		check("an Icon arrives with its name and label", ViewNodeBridge.getViewType(ViewNodeBridge.getChild(shown, 2)) == "Icon"
			&& ViewNodeBridge.getStringProperty(ViewNodeBridge.getChild(shown, 2), "name") == "mic-off");
		current = previous;
		ViewNodeBridge.rebuild();

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

		// --- the canon's tabs ---
		//
		// `DynamicTabs` read its titles from a parallel JSON array on a
		// "titles" property that nothing here ever emitted, so every tab of a
		// received tree was drawn "Tab 1", "Tab 2". And its selection was a
		// local @State, which no tree could reach -- the canon says the
		// selection is the application's so that a tap somewhere else can
		// bring a tab back.
		var bar = new nui.Node("Tabs").prop("selectedIndex", nui.PropValue.PInt(2))
			.child(new nui.Node("Tab").prop("label", nui.PropValue.PString("Source")));
		var barSource = new nui.SelfSource(() -> bar);
		check("a received Tabs offers its selection as its bound value",
			sui.nui.Received.stringProp(barSource, bar, "value") == "2",
			sui.nui.Received.stringProp(barSource, bar, "value"));
		check("and a title is the Tab's own label, not a parallel array",
			sui.nui.Received.stringProp(barSource, bar.children[0], "label") == "Source");

		// --- the canon's `clip`, both ways ---
		//
		// `DynamicView.swift` switches on sui's OWN spelling of a modifier, so
		// a name the Haxe side forgets to rename falls through its
		// `default: break` and nothing happens. `clip` did exactly that.
		var cutNode = new nui.Node("VStack").modifier({type: nui.Modifiers.CLIP});
		check("a received clip is renamed into the one Swift switches on",
			sui.nui.Received.modifierType(new nui.SelfSource(() -> cutNode), cutNode, 0) == "Clip");

		// And out. A rectangle IS the canon's clip; the other shapes are
		// SwiftUI's own and stay unnamed, because a receiver told "clip" cuts
		// at the edge, which a capsule does not.
		var cut:sui.View = new sui.ui.Text("x");
		cut.clip();
		var said = sui.nui.Describe.describe(cut);
		check("and a clipped view describes itself by the canonical name",
			[for (m in said.modifiers) m.type].indexOf(nui.Modifiers.CLIP) >= 0);

		ViewNodeBridge.readThrough(null);
		check("null hands the screen back", !ViewNodeBridge.reading() && ViewNodeBridge.getRoot() != again);

		Sys.println(fails == 0 ? "\nall good" : '\n$fails failed');
		Sys.exit(fails == 0 ? 0 : 1);
	}
}
