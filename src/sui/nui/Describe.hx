package sui.nui;

import sui.View;
import nui.Node;
import nui.PropValue;

/**
	Describes a sui view tree as `nui` nodes — the outward half a detached
	surface needs (Companion projection now, widget snapshots in P4a). Mirror
	of cui's `Describe` and wui's `FromViews`.

	`ViewSource` lets a foreign consumer *walk* a sui tree through the pull
	contract; this produces a `Node` tree outright, which is what
	`nui.Snapshot.project` eats. The pull contract cannot enumerate props — a
	walker asks by name — while a projection must carry everything.

	## The canon

	Types and props are the CANONICAL mui names — `Text`/`text`,
	`Button`/`label`+`onClick`, `Toggle`/`isOn`+`onToggle`,
	`TextInput`/`text`+`onText`, `Slider`/`value`+`onValue` — never sui's
	spellings (`textBinding`, `isOnBinding`), so a snapshot of a sui-served
	tree and of a cui- or wui-served one look the same on the wire and one
	sink renders both.

	## Describing samples — and on sui, sampling means resolving

	`LiveProps` builds every node with neutral values and hangs the real
	expression on `liveBuild`; the true values exist only when the thunk
	runs. So each node is RESOLVED first (`liveBuild()`, the same move
	`ViewSource.valueOf` makes), which is also what subscribes the projecting
	effect to the cells the tree displays — liveness is the effect around
	the describe. A `ConditionalView`'s condition is evaluated live and a
	`ForEach` spliced into its siblings, both through `ViewSource`'s own
	statics rather than a second copy of that knowledge.

	## Two-way controls

	sui bindings are NAME-routed (a `Toggle` holds the cell's name, not the
	cell). The change callbacks look the name up in the state registry and
	`set()` the parsed value — deliberately `set`, not `_applyFromSwift`'s
	`applyExternal`: a remote tap did NOT originate on this machine's Swift
	side, so the local SwiftUI must hear about it too.

	## Identity

	sui trees carry no sibling keys (the positional stance `ViewSource.keyOf`
	documents). Keys stay null; the receiving renderer's identity is
	positional too, and `Snapshot`'s place-keyed action ids still hold.
**/
@:access(sui.nui.ViewSource)
@:access(sui.state.State)
class Describe {
	/** Describe a view tree, or an empty root when there is nothing. **/
	public static function describe(view:View):Node {
		if (view == null) return new Node("VStack");
		var expansion:Array<Node> = [];
		if (expanded(view, expansion)) {
			var root = new Node("VStack");
			for (child in expansion) root.child(child);
			return root;
		}
		return node(view);
	}

	/**
		Resolve a node to its sampled self: the `liveBuild` thunk holds the
		real values (LiveProps built the node with neutral ones). Guarded
		loop, because a thunk's product could in principle carry a thunk.
	**/
	static function resolved(view:View):View {
		var current = view;
		var guard = 0;
		while (current != null && current.liveBuild != null && guard++ < 8) {
			var next = current.liveBuild();
			if (next == null || next == current) break;
			current = next;
		}
		return current;
	}

	/**
		Nodes with no rendering of their own, expanded before the wire sees
		them. Conditions and loops go through `ViewSource`'s own statics —
		one copy of that knowledge, not two.
	**/
	static function expanded(view:View, into:Array<Node>):Bool {
		if (Std.isOfType(view, sui.ui.ConditionalView)) {
			// Sampled live: the branch construction froze goes stale the
			// moment the cell changes. `null` means the condition named a
			// cell this process does not have — unanswerable, so nothing is
			// described rather than half a screen on a guess.
			var holds = ViewSource.conditionHolds(view);
			if (holds != null) {
				var v:sui.ui.ConditionalView = cast view;
				var taken = holds ? v.trueView : v.falseView;
				if (taken != null && !expanded(taken, into)) into.push(node(taken));
			}
			return true;
		}
		if (Std.isOfType(view, sui.ui.ForEach)) {
			var items = ViewSource.forEachItems(view);
			if (items != null) {
				for (item in items) {
					if (item == null) continue;
					if (!expanded(item, into)) into.push(node(item));
				}
			}
			return true;
		}
		if (Std.isOfType(view, sui.ViewComponent)) {
			var body = (cast view : sui.ViewComponent).body();
			if (body != null && body != view && !expanded(body, into)) into.push(node(body));
			return true;
		}
		return false;
	}

	/** A named cell's current value, read so the projecting effect
		subscribes — `get()`, not `peek()`: a remote panel showing a toggle
		must re-project when the toggle changes locally. **/
	static function cellValue(name:Null<String>):Null<Dynamic> {
		if (name == null || name == "") return null;
		var cell:Dynamic = sui.state.State._registry.get(name);
		if (cell == null) return null;
		return (cell : sui.state.State<Dynamic>).get();
	}

	/** Write a named cell from a remote edit. `set`, not `applyExternal`:
		the edit came from ANOTHER machine, so this machine's own SwiftUI
		must hear the change like any local write. Type inferred from the
		current value, the `_applyFromSwift` rule. **/
	static function cellWrite(name:Null<String>, raw:String):Void {
		if (name == null || name == "") return;
		var cell:Dynamic = sui.state.State._registry.get(name);
		if (cell == null) return;
		var s:sui.state.State<Dynamic> = cell;
		var current:Dynamic = s.peek();
		var parsed:Dynamic =
			if (Std.isOfType(current, Bool)) raw == "true"
			else if (Std.isOfType(current, Int)) {
				var i = Std.parseInt(raw);
				i != null ? i : Std.int(Std.parseFloat(raw));
			}
			else if (Std.isOfType(current, Float)) Std.parseFloat(raw)
			else if (Std.isOfType(current, String)) raw
			else return;
		s.set(parsed);
	}

	static function node(view:View):Node {
		var v = resolved(view);
		if (v == null) return new Node("VStack");
		var out:Node;

		// Most-derived first where hierarchies nest; sui types are mostly
		// flat classes over a property-bag View, so class dispatch is safe.
		if (Std.isOfType(v, sui.ui.Text)) {
			var t:sui.ui.Text = cast v;
			out = new Node("Text").prop("text", PString(t.content != null ? t.content : ""));

		} else if (Std.isOfType(v, sui.ui.Button)) {
			var b:sui.ui.Button = cast v;
			var action = b.action;
			out = new Node("Button")
				.prop("label", PString(b.label != null ? b.label : ""))
				.prop("onClick", PCallback(action != null ? action : function() {}));

		} else if (Std.isOfType(v, sui.ui.Toggle)) {
			var t:sui.ui.Toggle = cast v;
			var name = t.isOnBinding;
			var current = cellValue(name);
			out = new Node("Toggle")
				.prop("label", PString(t.label != null ? t.label : ""))
				.prop("isOn", PBool(current == true))
				.prop("onToggle", PCallbackBool(on -> cellWrite(name, on ? "true" : "false")));

		} else if (Std.isOfType(v, sui.ui.TextField)) {
			var f:sui.ui.TextField = cast v;
			var name = f.textBinding;
			var current = cellValue(name);
			out = new Node("TextInput")
				.prop("text", PString(Std.isOfType(current, String) ? (current : String) : ""))
				.prop("placeholder", PString(f.placeholder != null ? f.placeholder : ""))
				.prop("onText", PCallbackString(s -> cellWrite(name, s)));

		} else if (Std.isOfType(v, sui.ui.Slider)) {
			var s:sui.ui.Slider = cast v;
			var name = s.valueBinding;
			var current = cellValue(name);
			var value = Std.isOfType(current, Float) || Std.isOfType(current, Int) ? (current : Float) : 0.0;
			out = new Node("Slider")
				.prop("value", PFloat(value))
				.prop("min", PFloat(s.rangeMin))
				.prop("max", PFloat(s.rangeMax))
				.prop("onValue", PCallbackFloat(f -> cellWrite(name, Std.string(f))));

		} else if (Std.isOfType(v, sui.ui.ProgressView)) {
			// The mui facade drops its `value` argument today (it calls
			// `super(label)` only), so a mui-authored ProgressView has no
			// bound value to sample — label-only is the honest wire shape,
			// and a sui-native one with a binding still carries it.
			var p:sui.ui.ProgressView = cast v;
			var current = cellValue(p.valueBinding);
			out = new Node("ProgressView")
				.prop("label", PString(p.label != null ? p.label : ""));
			if (Std.isOfType(current, Float) || Std.isOfType(current, Int)) {
				var total = p.total > 0 ? p.total : 1.0;
				out.prop("value", PFloat((current : Float) / total));
			}

		} else if (Std.isOfType(v, sui.ui.Spacer)) {
			out = new Node("Spacer");

		} else if (v.viewType == "Divider") {
			out = new Node("Divider");

		} else if (Std.isOfType(v, sui.ui.HStack)) {
			var h:sui.ui.HStack = cast v;
			out = new Node("HStack");
			if (h.spacing != null) out.prop("spacing", PFloat(h.spacing));
			withChildren(out, v);

		} else if (Std.isOfType(v, sui.ui.VStack)) {
			var st:sui.ui.VStack = cast v;
			out = new Node("VStack");
			if (st.spacing != null) out.prop("spacing", PFloat(st.spacing));
			withChildren(out, v);

		} else if (Std.isOfType(v, sui.ui.ScrollView)) {
			out = new Node("ScrollView");
			withChildren(out, v);

		} else {
			// Loud rather than invisible: the receiving side draws "?Name"
			// and the name says whose. viewType is the honest short name on
			// a property-bag view; the class name backs it up.
			var name = v.viewType != null && v.viewType != "" ? v.viewType : {
				var full = Type.getClassName(Type.getClass(v));
				full.substr(full.lastIndexOf(".") + 1);
			};
			out = new Node(name);
			withChildren(out, v);
		}

		return out;
	}

	static function withChildren(out:Node, view:View):Void {
		if (view.children == null) return;
		for (child in view.children) {
			if (child == null) continue;
			var into:Array<Node> = [];
			if (expanded(child, into)) {
				for (n in into) out.child(n);
			} else {
				out.child(node(child));
			}
		}
	}
}
