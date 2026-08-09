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

	/** Expanded child lists, one generation of the tree — see `childrenOf`. **/
	var _children:haxe.ds.ObjectMap<View, Array<View>>;

	/** Nodes standing where exactly one view is expected — see `resolveWalked`. **/
	var _wrapped:haxe.ds.ObjectMap<View, View>;

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
		n = resolveWalked(n);
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
		n = resolveWalked(n);
		if (n == null) return 0;
		return childrenOf(n).length;
	}

	public function childAt(n:View, index:Int):View {
		n = resolveWalked(n);
		if (n == null || index < 0) return null;
		var children = childrenOf(n);
		return index >= children.length ? null : children[index];
	}

	// --- Nodes with no rendering of their own -------------------------------
	//
	// sui was written for a transpiler: a ViewComponent became a Swift struct,
	// a ForEach became a `ForEach(0..<n)`, a ConditionalView became an `if`.
	// All three were *read* at compile time, so none of them ever had to
	// describe itself to a walker -- and a walker is what the dynamic renderer
	// is. Left alone they arrive as node types no renderer has a branch for,
	// and draw nothing.
	//
	// They are expanded here instead, so the renderer never meets them. The
	// alternative -- a branch per case in DynamicView.swift -- would mean
	// teaching Swift to call back into Haxe to run a component's body() and a
	// loop's builder, which is the walk it already does, spelled twice.

	/**
		Expand a node into the one view it stands for.

		A `ViewComponent` is its `body()`. A `ConditionalView` is the branch its
		condition selects — the tree is rebuilt whenever state changes, so the
		condition can simply be *read* here, and the renderer never learns what
		an `if` is.

		Loops are the exception that cannot be one view: see `childrenOf`. Where
		one is nonetheless expected — the root, a `NavigationStack`'s content —
		it becomes the stack the transpiler emitted there.
	**/
	public function resolveWalked(n:View):View {
		if (n == null) return null;

		if (_wrapped == null) _wrapped = new haxe.ds.ObjectMap();
		var cached = _wrapped.get(n);
		if (cached != null) return cached;

		var current = n;
		var guard = 0;
		while (current != null && guard++ < 64) {
			var next = expandOne(current);
			if (next == null || next == current) break;
			current = next;
		}

		if (current != n) _wrapped.set(n, current);
		return current;
	}

	/** One step of expansion, or null when the node stands for itself. **/
	function expandOne(n:View):Null<View> {
		if (Std.isOfType(n, sui.ViewComponent)) {
			var produced = n.body();
			if (produced == null || produced == n) return null;
			// `ViewComponent.body()` returns a bare `View` when the component
			// never overrode it. That is a component with nothing in it, not a
			// node to draw: the renderer has no `View` branch, so it would have
			// gone to the unknown-type case for what is really an empty body.
			return isBare(produced) ? empty() : produced;
		}

		if (n.viewType == "ConditionalView") {
			var holds = conditionHolds(n);
			// Unresolvable: the condition named a field on the generated
			// appState, which does not exist here. Taking the else-branch would
			// be indistinguishable from a genuine `false` -- and would put half
			// the screen up on a guess. Neither branch is the only honest answer.
			if (holds == null) return empty();
			var taken = holds ? Reflect.field(n, "trueView") : Reflect.field(n, "falseView");
			// No else branch and a false condition: nothing to draw. An empty
			// stack is the honest answer -- null would read as "no such node"
			// to a walker that is holding one.
			return taken == null ? empty() : cast taken;
		}

		if (n.viewType == "ForEach") {
			var items = forEachItems(n);
			if (items == null) return null;
			var stack = new sui.ui.VStack(null, null, items);
			return stack;
		}

		return null;
	}

	/**
		Whether a `ConditionalView`'s condition holds.

		Its `stateName` field is declared `String` but assigned from a `Dynamic`
		parameter, so it holds whatever was passed: a `State` when the app wrote
		`new ConditionalView(isLoggedIn, ...)`, a plain string when it wrote the
		transpiler's form, `new ConditionalView("isLoggedIn", ...)`.

		Only the first can be answered here. The string names a field the
		generated Swift would have read off `appState`; at runtime it is a name
		with nothing to look it up in. That form is refused at compile time
		rather than guessed at -- see `sui.macros.SwiftGenerator`.
	**/
	static function conditionHolds(n:View):Null<Bool> {
		var cond:Dynamic = Reflect.field(n, "stateName");
		if (cond == null) return null;
		if (Std.isOfType(cond, rui.state.State)) {
			var value:Dynamic = (cast cond : rui.state.State<Dynamic>).get();
			return value == true;
		}
		return null;
	}

	/** A node with nothing in it, in a type the renderer can draw. **/
	static inline function empty():View {
		return new sui.ui.VStack(null, null, []);
	}

	/** A plain `sui.View`, carrying no type of its own. **/
	static function isBare(n:View):Bool {
		return Type.getClass(n) == View;
	}

	/**
		A node's children, with every `ForEach` among them replaced by the views
		it yields.

		A loop is not a thing on screen: it is siblings. Splicing it into the
		parent is the same answer a component gets, and it keeps the loop out of
		the renderer's vocabulary, where a branch would have had to reproduce
		the parent's layout to place items as siblings rather than in a box.
	**/
	function childrenOf(n:View):Array<View> {
		if (n.children == null || n.children.length == 0) return [];

		// Memoised per generation: `childAt` is called once per index, and
		// expanding on each call would re-run every item's builder n times over.
		// The host replaces the source on rebuild, so nothing here goes stale.
		if (_children == null) _children = new haxe.ds.ObjectMap();
		var cached = _children.get(n);
		if (cached != null) return cached;

		var out:Array<View> = [];
		var expanded = false;
		for (child in n.children) {
			var items = child != null && child.viewType == "ForEach" ? forEachItems(child) : null;
			if (items == null) {
				out.push(child);
			} else {
				expanded = true;
				for (item in items) out.push(item);
			}
		}

		var result = expanded ? out : n.children;
		_children.set(n, result);
		return result;
	}

	/**
		The views a `ForEach` yields, or null when it is one this path cannot run.

		sui's `ForEach` has three shapes, and only two of them are values:

		- `ForEach(items, item -> view)` — the builder is a closure; call it.
		- `ForEach.byIndex(items, i -> view)` — same, with the index.
		- `ForEach(items, "i", Text.withState("{items[i].title}"))` — the legacy
		  form, whose body is a *string template* the transpiler resolved against
		  the generated `appState`. There is nothing to call here, and rendering
		  the template verbatim would put `{items[i].title}` on screen. It is
		  refused at compile time instead.
	**/
	static function forEachItems(n:View):Null<Array<View>> {
		var builder:Dynamic = Reflect.field(n, "builder");
		if (builder == null || !Reflect.isFunction(builder)) return null;

		var source:Dynamic = Reflect.field(n, "arrayName");
		if (source == null) return [];
		if (Std.isOfType(source, rui.state.State)) source = (cast source : rui.state.State<Dynamic>).get();
		if (source == null || Std.isOfType(source, String)) return [];

		var items:Array<Dynamic> = [];
		if (Std.isOfType(source, Array)) {
			items = cast source;
		} else {
			// Anything iterable: `rui.structures.ImmutableList` is the other
			// collection a view is allowed to read.
			var makeIterator:Dynamic = Reflect.field(source, "iterator");
			if (!Reflect.isFunction(makeIterator)) return [];
			var iter:Dynamic = Reflect.callMethod(source, makeIterator, []);
			while (iter.hasNext()) items.push(iter.next());
		}

		// `byIndex` hands the lambda the position, not the element.
		var byIndex = Reflect.field(n, "itemName") == "_byIndex";

		var out:Array<View> = [];
		for (i in 0...items.length) {
			var arg:Dynamic = byIndex ? i : items[i];
			var view:Dynamic = Reflect.callMethod(null, builder, [arg]);
			if (view != null) out.push(cast view);
		}
		return out;
	}

	public function hasProp(n:View, key:String):Bool {
		n = resolveWalked(n);
		if (n == null || n.properties == null) return false;
		return n.properties.exists(key);
	}

	public function stringProp(n:View, key:String):String {
		n = resolveWalked(n);
		if (n == null || n.properties == null) return "";
		var val:Dynamic = n.properties.get(key);
		return val != null ? Std.string(val) : "";
	}

	public function intProp(n:View, key:String):Int {
		n = resolveWalked(n);
		if (n == null || n.properties == null) return 0;
		var val:Dynamic = n.properties.get(key);
		return val != null ? cast(val, Int) : 0;
	}

	public function floatProp(n:View, key:String):Float {
		n = resolveWalked(n);
		if (n == null || n.properties == null) return 0.0;
		var val:Dynamic = n.properties.get(key);
		return val != null ? cast(val, Float) : 0.0;
	}

	public function boolProp(n:View, key:String):Bool {
		n = resolveWalked(n);
		if (n == null || n.properties == null) return false;
		var val:Dynamic = n.properties.get(key);
		return val != null ? cast(val, Bool) : false;
	}

	public function modifierCount(n:View):Int {
		n = resolveWalked(n);
		if (n == null || n.modifierChain == null) return 0;
		return n.modifierChain.length;
	}

	public function modifierType(n:View, index:Int):String {
		n = resolveWalked(n);
		if (n == null || n.modifierChain == null || index < 0 || index >= n.modifierChain.length) return "";
		return Type.enumConstructor(n.modifierChain[index]);
	}

	public function modifierFloat(n:View, index:Int, param:Int):Float {
		n = resolveWalked(n);
		if (n == null || n.modifierChain == null || index < 0 || index >= n.modifierChain.length) return 0.0;
		var params = Type.enumParameters(n.modifierChain[index]);
		if (param < 0 || param >= params.length) return 0.0;
		var val:Dynamic = params[param];
		if (Std.isOfType(val, Float)) return val;
		if (Std.isOfType(val, Int)) return cast(val, Int) * 1.0;
		return 0.0;
	}

	public function modifierString(n:View, index:Int, param:Int):String {
		n = resolveWalked(n);
		if (n == null || n.modifierChain == null || index < 0 || index >= n.modifierChain.length) return "";
		var params = Type.enumParameters(n.modifierChain[index]);
		if (param < 0 || param >= params.length) return "";
		return Std.string(params[param]);
	}

	public function actionId(n:View):Int {
		n = resolveWalked(n);
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
		n = resolveWalked(n);
		if (n == null) return;
		var action:Dynamic = Reflect.field(n, "action");
		if (action != null) action();
	}
}
