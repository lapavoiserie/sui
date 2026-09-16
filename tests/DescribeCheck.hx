import mui.App;
import mui.View;
import mui.ui.Text;
import mui.ui.VStack;
import mui.ui.Button;
import mui.ui.Toggle;
import mui.ui.Picker;
import mui.ui.ToggleBinding;
import nui.PropValue;
import nui.PropValue.PropValueTools;

/**
	The sui end of the Companion pipe: a real mui-facade tree — with the
	LiveProps deferral sui puts on every displayed value — is DESCRIBED to
	canonical nodes through the shared hook, PROJECTED to a snapshot, carried
	as JSON, and the ids are invoked the way a remote sink would: the button's
	closure runs, and a toggle edit lands in the @:state cell.

	Compiled with the full mui chain, judged on the exit code.

	    ./tests/run_describe.sh
**/
class DescribeCheck extends App {
	static var fails = 0;

	static function check(label:String, ok:Bool) {
		if (!ok) fails++;
		Sys.println((ok ? "  ok   " : "  FAIL ") + label);
	}

	@:state var lit:Bool = false;
	@:state var count:Int = 3;
	@:state var transition:Int = 1;

	override function body():View {
		return new VStack([
			// The interpolation is a LiveProps thunk: the describer must
			// resolve it, or the wire carries the neutral "".
			new Text('count: $count'),
			new Button("Go", () -> taps.push("go")),
			new Toggle("Lamp", (lit_ : ToggleBinding)),
			new Picker("Transition", ["Cut", "Fade", "Wipe"], transition_),
		], 8);
	}

	static var taps:Array<String> = [];

	static function main() {
		Sys.println("sui — describe, and the Companion pipe");

		var app = new DescribeCheck();
		var described = mui.surface.Describe.describe(app.body());
		check("the hook answers", described != null);

		// --- The canon, with LiveProps resolved ---
		check("a stack describes with its spacing", described.type == "VStack"
			&& PropValueTools.asFloat(described.props.get("spacing")) == 8);
		check("a deferred value is sampled, not neutral",
			described.children[0].type == "Text"
			&& PropValueTools.asString(described.children[0].props.get("text")) == "count: 3");
		var btn = described.children[1];
		check("Button carries label and onClick", btn.type == "Button"
			&& PropValueTools.asString(btn.props.get("label")) == "Go"
			&& btn.props.get("onClick") != null);
		var tog = described.children[2];
		check("Toggle follows the change-key canon (isOn/onToggle)", tog.type == "Toggle"
			&& PropValueTools.asBool(tog.props.get("isOn")) == false
			&& tog.props.get("onToggle") != null);

		// A described two-way control writes through to the cell — and via
		// set(), so the local platform would hear it too.
		switch (PropValueTools.resolve(tog.props.get("onToggle"))) {
			case PCallbackBool(fn): fn(true);
			case _:
		}
		check("a described binding writes back to the state", app.lit == true);

		var pick = described.children[3];
		check("a Picker describes canonically: its options as Text children", pick.type == "Picker"
			&& pick.children.length == 3 && PropValueTools.asString(pick.children[2].props.get("text")) == "Wipe"
			&& PropValueTools.asString(pick.props.get("label")) == "Transition");
		check("its selection is the cell's index", PropValueTools.asInt(pick.props.get("selectedIndex")) == 1);
		switch (PropValueTools.resolve(pick.props.get("onSelect"))) {
			case PCallbackInt(fn): fn(2);
			case _:
		}
		check("a choice from far away writes the index into the cell", app.transition == 2);

		// Re-describe: the sample must follow the cell.
		var again = mui.surface.Describe.describe(app.body());
		check("a re-describe samples the new value",
			PropValueTools.asBool(again.children[2].props.get("isOn")) == true);

		// A native component is sent as the node it was made from, typed props
		// intact: the far side's registry keys on exactly that.
		var native = mui.surface.Describe.describe(new sui.ui.VStack(null, null, [
			new sui.ui.NativeComponent(new nui.Node("LevelMeter")
				.prop("stream", PString("vu.master"))
				.prop("floorDb", PFloat(-60.0)))
		]));
		var sent = native.children[0];
		check("a native component describes as its own node", sent.type == "LevelMeter"
			&& PropValueTools.asString(sent.props.get("stream")) == "vu.master"
			&& sent.props.get("floorDb").match(PFloat(-60.0)));

		// --- The pipe: project -> wire -> invoke like a remote sink ---
		var table = new nui.Snapshot.ActionTable();
		var snap = nui.Snapshot.project(described, table);
		var far = nui.Snapshot.fromJson(nui.Snapshot.toJson(snap));
		check("the snapshot carries the action ids",
			far.children[1].actions.get("onClick") != null
			&& far.children[2].actions.get("onToggle") != null);

		table.invoke(far.children[1].actions.get("onClick"));
		check("a remote tap runs the button's closure", taps.length == 1 && taps[0] == "go");

		app.lit = false;
		table.invoke(far.children[2].actions.get("onToggle"), "true");
		check("a remote toggle edit lands in the @:state cell", app.lit == true);

		Sys.println(fails == 0 ? "\nall good" : '\n$fails failed');
		Sys.exit(fails == 0 ? 0 : 1);
	}
}
