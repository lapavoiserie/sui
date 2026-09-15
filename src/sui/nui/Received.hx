package sui.nui;

import nui.Node;
import nui.PropValue;
import nui.PropValue.PropValueTools;
import nui.SelfSource;

/**
	How `sui`'s renderer reads a tree it did not build.

	A received tree is `nui.Node`s in the **canonical** vocabulary every
	describer emits — `Toggle` with `isOn`/`onToggle`, `TextInput` with
	`text`/`placeholder`/`onText`, `Slider` with `value`/`min`/`max`/`onValue`,
	modifiers named `padding`, `foregroundColor`, `opacity` — and it is read
	directly, through `nui.SelfSource`, the way `aui` reads one: no copy into
	`sui` views, so nothing can drift between a copy and the tree.

	`DynamicView.swift` asks its own questions, though, in `sui`'s spelling: a
	`TextField`, a control's `value` and the `path` its edits go to, a
	`ForegroundColor` modifier. This is the one place those questions are
	answered for a canonical node. Kept apart from `ViewNodeBridge`, which only
	decides whose tree a node belongs to.

	## Edits go home as actions

	A received tree carries values, not cells: the cells stayed with the
	application that served it. So a control's `path` is the id of the action
	its node carries, and an edit written to it runs that action with the new
	value — which, on an inflated tree, sends it home. The id is the node's
	position among the tree's actions (`SelfSource.actionId`), so it names the
	same control in the next generation.
**/
@:access(nui.SelfSource)
class Received {
	/** What a `path` answers for a control whose edits run its action. **/
	public static inline var PATH_PREFIX = "nui:";

	/** The type the renderer switches on. **/
	public static function typeOf(source:SelfSource, n:Node):String {
		var type = source.typeOf(n);
		return switch (type) {
			case "TextInput": "TextField";
			case "Box": "ZStack";
			case _: type;
		}
	}

	/** A property, as the renderer names it. **/
	public static function stringProp(source:SelfSource, n:Node, key:String):String {
		if (n == null) return "";
		return switch [n.type, key] {
			case ["Toggle", "value"]: source.boolProp(n, "isOn") ? "true" : "false";
			case ["TextInput", "value"]: source.stringProp(n, "text");
			case ["TextInput", "label"]: source.stringProp(n, "placeholder");
			case [_, "path"]:
				var id = source.actionId(n);
				id < 0 ? "" : PATH_PREFIX + id;
			// sui's own controls bind by the name of a cell. A received control
			// has no cell here, and must not be mistaken for one that does.
			case [_, "textBinding" | "isOnBinding" | "valueBinding" | "selectionBinding" | "isoStateName"]: "";
			case _: text(n, key);
		}
	}

	/**
		Any value as the text the renderer parses. The contract's `stringProp`
		answers "" for a number, and the renderer reads every number as text —
		a stack's `spacing`, a slider's `min`, a meter's `floorDb`.
	**/
	static function text(n:Node, key:String):String {
		var v = PropValueTools.resolve(n.props.get(key));
		if (v == null) return "";
		return switch (v) {
			case PString(s): s;
			case PInt(i): Std.string(i);
			case PFloat(f): Std.string(f);
			case PBool(b): b ? "true" : "false";
			case _: "";
		}
	}

	/** A modifier's type, as the renderer names it; unknown ones pass through,
		and the renderer ignores what it does not know. **/
	public static function modifierType(source:SelfSource, n:Node, index:Int):String {
		var type = source.modifierType(n, index);
		return switch (type) {
			case "padding": source.modifierHasParam(n, index, 0) ? "Padding" : "PaddingDefault";
			case "font": "Font";
			case "bold": "Bold";
			case "italic": "Italic";
			case "foregroundColor": "ForegroundColor";
			case "backgroundColor": "Background";
			case "opacity": "Opacity";
			case "cornerRadius": "CornerRadius";
			case "disabled": "Disabled";
			case _: type;
		}
	}

	/**
		Apply an edit a control wrote to its `path`. False when the path is not
		one of ours — the caller then hands it to the application's data sink.
	**/
	public static function edit(source:SelfSource, path:String, raw:String):Bool {
		if (path == null || !StringTools.startsWith(path, PATH_PREFIX)) return false;
		var id = Std.parseInt(path.substr(PATH_PREFIX.length));
		var actions = source.actions;
		if (id == null || id < 0 || id >= actions.length) return true;
		var n = actions[id];
		rui.Signal.Scheduler.batch(() -> {
			for (key in ["onText", "onToggle", "onValue"]) {
				var v = PropValueTools.resolve(n.props.get(key));
				if (v == null) continue;
				switch (v) {
					case PCallbackString(fn):
						fn(raw);
					case PCallbackBool(fn):
						fn(raw == "true");
					case PCallbackFloat(fn):
						var f = Std.parseFloat(raw);
						if (!Math.isNaN(f)) fn(f);
					case PCallbackInt(fn):
						var f = Std.parseFloat(raw);
						if (!Math.isNaN(f)) fn(Math.round(f));
					case PCallback(fn):
						fn();
					case _:
						continue;
				}
				return;
			}
		});
		return true;
	}
}
