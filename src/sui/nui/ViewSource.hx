package sui.nui;

import nui.NodeSource;
import sui.View;

/**
	Describes a `sui` view tree through
	[nui's pull contract](https://lapavoiserie.github.io/nui/#/pull-mode).

	The node handle is `sui.View` itself: sui holds a live Haxe tree, so nothing
	needs copying — the same choice `cui` made.

	## Why this is a move, not an addition

	`sui.runtime.ViewNodeBridge` already walked this tree, accessor for accessor:
	`getViewType`/`typeOf`, `getChildCount`/`childCount`, `getStringProperty`/
	`stringProp`, `getModifierFloat`/`modifierFloat`, and the rest. That is not a
	coincidence — the pull contract was extracted largely *from* this bridge,
	then never handed back.

	Leaving both would be the ecosystem's most expensive recurring mistake: one
	piece of knowledge in two places, drifting apart silently, since a walk that
	answers a slightly different question does not crash — it renders something
	slightly wrong. So the walk lives here, and the bridge forwards to it.

	`ViewNodeBridge` keeps its static shape: it is called from C by symbol, and
	an interface has no static entry points.
**/
class ViewSource implements NodeSource<View> {
	final _root:View;

	public function new(root:View) {
		_root = root;
	}

	public function root():View
		return _root;

	/**
		The tree is rebuilt by re-running the app's `body()`, which the host
		drives through `ViewNodeBridge.rebuild()` — it replaces the root, so a
		source holds one generation of the tree.
	**/
	public function rebuild():Void {}

	public function typeOf(n:View):String {
		if (n == null) return "";
		var vt = n.viewType;
		if (vt == null) return "";
		// "sui.ui.VStack" -> "VStack": the contract's discriminant is the bare
		// type name, which is what a host switches on.
		var dot = vt.lastIndexOf(".");
		return dot >= 0 ? vt.substr(dot + 1) : vt;
	}

	/**
		sui has no notion of a sibling key yet, so identity is positional.

		Returning `null` is the contract's own answer for that, not a gap papered
		over: a host that rebuilds identity from scratch will recreate a control
		that merely moved. The day sui's lists carry keys, this is the one place
		to say so.
	**/
	public function keyOf(n:View):Null<String>
		return null;

	public function childCount(n:View):Int {
		if (n == null || n.children == null) return 0;
		return n.children.length;
	}

	public function childAt(n:View, index:Int):View {
		if (n == null || n.children == null || index < 0 || index >= n.children.length) return null;
		return n.children[index];
	}

	public function hasProp(n:View, key:String):Bool {
		if (n == null || n.properties == null) return false;
		return n.properties.exists(key);
	}

	public function stringProp(n:View, key:String):String {
		if (n == null || n.properties == null) return "";
		var val:Dynamic = n.properties.get(key);
		return val != null ? Std.string(val) : "";
	}

	public function intProp(n:View, key:String):Int {
		if (n == null || n.properties == null) return 0;
		var val:Dynamic = n.properties.get(key);
		return val != null ? cast(val, Int) : 0;
	}

	public function floatProp(n:View, key:String):Float {
		if (n == null || n.properties == null) return 0.0;
		var val:Dynamic = n.properties.get(key);
		return val != null ? cast(val, Float) : 0.0;
	}

	public function boolProp(n:View, key:String):Bool {
		if (n == null || n.properties == null) return false;
		var val:Dynamic = n.properties.get(key);
		return val != null ? cast(val, Bool) : false;
	}

	public function modifierCount(n:View):Int {
		if (n == null || n.modifierChain == null) return 0;
		return n.modifierChain.length;
	}

	public function modifierType(n:View, index:Int):String {
		if (n == null || n.modifierChain == null || index < 0 || index >= n.modifierChain.length) return "";
		return Type.enumConstructor(n.modifierChain[index]);
	}

	public function modifierFloat(n:View, index:Int, param:Int):Float {
		if (n == null || n.modifierChain == null || index < 0 || index >= n.modifierChain.length) return 0.0;
		var params = Type.enumParameters(n.modifierChain[index]);
		if (param < 0 || param >= params.length) return 0.0;
		var val:Dynamic = params[param];
		if (Std.isOfType(val, Float)) return val;
		if (Std.isOfType(val, Int)) return cast(val, Int) * 1.0;
		return 0.0;
	}

	public function modifierString(n:View, index:Int, param:Int):String {
		if (n == null || n.modifierChain == null || index < 0 || index >= n.modifierChain.length) return "";
		var params = Type.enumParameters(n.modifierChain[index]);
		if (param < 0 || param >= params.length) return "";
		return Std.string(params[param]);
	}

	public function actionId(n:View):Int {
		if (n == null) return -1;
		var id:Dynamic = Reflect.field(n, "actionId");
		return id != null ? cast(id, Int) : -1;
	}

	/**
		Run the node's action.

		The static bridge routes taps through an integer id into the `Callbacks`
		store, because a Haxe closure captured by a Swift/ARC closure is invisible
		to the hxcpp GC. The dynamic path has no such problem: the live tree is a
		GC root, so the closure sitting on the node stays reachable — hence the
		direct call, with no id and no `Callbacks` indirection.
	**/
	public function invokeAction(n:View):Void {
		if (n == null) return;
		var action:Dynamic = Reflect.field(n, "action");
		if (action != null) action();
	}
}
