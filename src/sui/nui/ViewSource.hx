package sui.nui;

import nui.NodeSource;
import sui.View;
import sui.runtime.ReadScope;

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

	/**
		The node a *value* should be read from: expanded, then through its thunk.

		`LiveProps` builds a node with neutral values and hangs the real
		expression on `liveBuild`. Calling it here is what puts the state read at
		the moment the renderer asks — inside the SwiftUI view that displays the
		value — rather than at the moment `body()` ran.

		Deliberately **not** memoised, unlike the child lists. A memo would be
		right if a value could only change with a new tree, and the whole point
		is that it can change without one: the leaf asks again, and must get the
		new answer.
	**/
	public function valueOf(n:View):View {
		var resolved = resolveWalked(n);
		if (resolved == null) return null;
		return resolved.liveBuild != null ? resolved.liveBuild() : resolved;
	}

	/**
		The cells a node's value depends on, by name.

		Evaluated inside a `ReadScope`, so the answer is whatever the thunk
		actually read — not a guess from the expression's shape. A node with no
		thunk depends on nothing: its value was a constant.

		This is what SwiftUI cannot work out for itself, and what lets a write
		reach one view instead of the tree.
	**/
	public function valueDependencies(n:View):Array<String> {
		var resolved = resolveWalked(n);
		if (resolved == null || resolved.liveBuild == null) return [];
		ReadScope.begin();
		try {
			resolved.liveBuild();
		} catch (_:Dynamic) {}
		return ReadScope.end();
	}

	/** Cells read while expanding the tree — see `structuralNames`. **/
	var _walkStructural:Map<String, Bool>;

	/**
		The cells that decide the tree's **shape**, as far as this source knows.

		Not everything structural is read during `body()`. A `ForEach` holds its
		list and a `ConditionalView` its condition, and both are read lazily —
		when the walk reaches them, which is after `body()` has returned. Left to
		`body()` alone, adding an item to a list would have been classified as a
		value change and the new row would never have appeared.

		So expansion runs inside a scope of its own and merges here. A component's
		`body()` counts too: what it reads shapes its subtree.
	**/
	public function structuralNames():Array<String> {
		if (_walkStructural == null) return [];
		return [for (name in _walkStructural.keys()) name];
	}

	/** Cells some node displays — see `classify`. **/
	var _valueNames:Map<String, Bool>;

	public function valueNames():Array<String> {
		if (_valueNames == null) return [];
		return [for (name in _valueNames.keys()) name];
	}

	/**
		Walk the whole tree once, so both sets are complete before anyone asks.

		Expansion is lazy: a `ForEach`'s list is read when the walk reaches it,
		and a node's thunk when its value is asked for. Classifying a write
		before that happened answered "not structural" for a list nobody had
		looked at yet — and adding a row would have updated no row at all.

		So the source classifies itself when it is built. It costs one traversal
		and one thunk evaluation per node, which is what the renderer's first
		frame does anyway; it buys an answer that does not depend on what has
		been drawn yet.
	**/
	public function classify():Void {
		if (_valueNames == null) _valueNames = new Map();
		visit(_root, 0);
	}

	function visit(n:View, depth:Int):Void {
		// A tree deep enough to hit this is a cycle, not a view.
		if (n == null || depth > 512) return;
		for (name in valueDependencies(n)) _valueNames.set(name, true);
		var count = childCount(n);
		for (i in 0...count) visit(childAt(n, i), depth + 1);
	}

	/**
		`forEachItems`, inside a scope — the splice path's missing half.

		`expandOne` records what expanding a node reads; this splice path read
		the ForEach's list BARE, so the list never counted as structural. The
		symptom, paid for on macOS: a menu action wrote the list, the count
		label updated (a value dependency), and the rows never changed —
		`isStructural` answered false because nothing had ever recorded the
		read that shapes them. Same scope, same merge, as expandOne.
	**/
	function splicedItems(n:View):Null<Array<View>> {
		ReadScope.begin();
		var items = forEachItems(n);
		var read = ReadScope.end();
		if (read.length > 0) {
			if (_walkStructural == null) _walkStructural = new Map();
			for (name in read) _walkStructural.set(name, true);
		}
		return items;
	}

	/** One step of expansion, or null when the node stands for itself. **/
	function expandOne(n:View):Null<View> {
		ReadScope.begin();
		var produced = expandStep(n);
		var read = ReadScope.end();
		if (read.length > 0) {
			if (_walkStructural == null) _walkStructural = new Map();
			for (name in read) _walkStructural.set(name, true);
		}
		return produced;
	}

	function expandStep(n:View):Null<View> {
		// A bare `sui.View` carries no type of its own -- it is what `App.body()`
		// and `ViewComponent.body()` return before anything overrides them. The
		// renderer has no `View` branch, so left alone it drew a placeholder for
		// what is really "nothing here yet".
		if (isBare(n)) return n.children != null && n.children.length > 0 ? null : empty();

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

		Both are answerable. The string names a field the generated Swift would
		have read off `appState`; here it is looked up in the registry every
		`sui.state.State` joins when it is constructed — the same registry the
		shared-memory bridge queries. A name that resolves to nothing is the one
		case left: not `false`, which would put half a screen up on a guess, but
		unanswerable.
	**/
	static function conditionHolds(n:View):Null<Bool> {
		var cond:Dynamic = Reflect.field(n, "stateName");
		if (cond == null) return null;
		if (Std.isOfType(cond, rui.state.State)) {
			var value:Dynamic = (cast cond : rui.state.State<Dynamic>).get();
			return value == true;
		}
		if (Std.isOfType(cond, String)) {
			var name:String = cast cond;
			if (!sui.state.State.existsByName(name)) return null;
			return sui.state.State.peekByName(name) == true;
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
		var declared = contentOf(n);
		if (declared != null) return declared;

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
			var items = child != null && child.viewType == "ForEach" ? splicedItems(child) : null;
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
		A `TabView`'s tabs, or null for anything else.

		Its contents are pushed into `children`, but the label and icon beside
		each one are not: they sit in `tabs`, which the transpiler read directly.
		A host drawing a tab bar needs them, and has nothing else to get them
		from.
	**/
	static function tabsOf(n:View):Null<Array<Dynamic>> {
		if (n == null || n.viewType != "TabView") return null;
		var tabs:Dynamic = Reflect.field(n, "tabs");
		return tabs == null ? null : cast tabs;
	}

	public function tabCount(n:View):Int {
		var tabs = tabsOf(resolveWalked(n));
		return tabs == null ? 0 : tabs.length;
	}

	public function tabTitle(n:View, index:Int):String {
		return tabField(n, index, "label");
	}

	public function tabIcon(n:View, index:Int):String {
		return tabField(n, index, "systemImage");
	}

	static function tabField(n:View, index:Int, key:String):String {
		var tabs = tabsOf(n);
		if (tabs == null || index < 0 || index >= tabs.length) return "";
		var value:Dynamic = Reflect.field(tabs[index], key);
		return value == null ? "" : Std.string(value);
	}

	/**
		Sub-views a node keeps **outside** `children`, or null for anything else.

		Three of sui's containers never filled `children`: the transpiler read
		their fields directly, so nothing needed them to be reachable by walking.
		Reporting zero children for them is a lie to the pull contract, and it
		draws an empty box -- which is what a `GroupBox` did.

		The classes are left alone; the *description* is corrected here, which is
		what a source is for. Any consumer benefits, not only this renderer.
	**/
	function contentOf(n:View):Null<Array<View>> {
		switch (n.viewType) {
			case "GroupBox" | "DisclosureGroup":
				var content:Dynamic = Reflect.field(n, "content");
				return content == null ? [] : (content : Array<View>);
			case "AdaptiveStack":
				var sidebar:Dynamic = Reflect.field(n, "sidebar");
				var detail:Dynamic = Reflect.field(n, "detail");
				var out:Array<View> = [];
				if (sidebar != null) out.push(cast sidebar);
				if (detail != null) out.push(cast detail);
				return out;
			case _:
				return null;
		}
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

	/**
		A named value carried by a node, from wherever the node keeps it.

		`properties` first, then the node's own **field** of that name. sui's
		views were written for a transpiler, which read `spacing`, `header`,
		`label` straight off the typed AST -- so almost nothing was ever put in
		the properties map, and a walker asking for a name got "" for a value
		sitting one field away.

		It was not a gap that announced itself: `new VStack(null, 16, [...])`
		drew with SwiftUI's default spacing, because `property("spacing")` found
		an empty map and the renderer read that as "unspecified". Every value on
		every node this path draws went the same way.
	**/
	static function rawValue(n:View, key:String):Null<Dynamic> {
		if (n == null) return null;
		if (n.properties != null) {
			var fromMap:Dynamic = n.properties.get(key);
			if (fromMap != null) return fromMap;
		}
		return Reflect.field(n, key);
	}

	public function hasProp(n:View, key:String):Bool {
		n = valueOf(n);
		return rawValue(n, key) != null;
	}

	public function stringProp(n:View, key:String):String {
		n = valueOf(n);
		var val = rawValue(n, key);
		if (val == null) return "";
		return describe(val);
	}

	/**
		One value, in the one form a host can switch on.

		An enum describes itself by its constructor -- `Center`, `Red`,
		`LargeTitle` -- with its parameters after it, so `Custom("#7c3aed")`
		crosses as `Custom(#7c3aed)`. A list joins with commas: a gradient's
		colours are the only lists a view carries, and a host that can read
		`Blue,Purple` needs no list protocol for them.

		`Std.string` is close to this on most targets and not on all of them,
		and the host compares these words exactly.
	**/
	static function describe(val:Dynamic):String {
		if (val == null) return "";
		if (Std.isOfType(val, Array)) {
			var arr:Array<Dynamic> = val;
			return [for (item in arr) describe(item)].join(",");
		}
		if (Reflect.isEnumValue(val)) {
			var name = Type.enumConstructor(val);
			var params = Type.enumParameters(val);
			if (params == null || params.length == 0) return name;
			return name + "(" + [for (p in params) Std.string(p)].join(",") + ")";
		}
		return Std.string(val);
	}

	public function intProp(n:View, key:String):Int {
		n = valueOf(n);
		var val = rawValue(n, key);
		if (val == null) return 0;
		if (Std.isOfType(val, Int)) return val;
		if (Std.isOfType(val, Float)) return Std.int(val);
		var parsed = Std.parseInt(Std.string(val));
		return parsed == null ? 0 : parsed;
	}

	public function floatProp(n:View, key:String):Float {
		n = valueOf(n);
		var val = rawValue(n, key);
		if (val == null) return 0.0;
		if (Std.isOfType(val, Float) || Std.isOfType(val, Int)) return val;
		var parsed = Std.parseFloat(Std.string(val));
		return Math.isNaN(parsed) ? 0.0 : parsed;
	}

	public function boolProp(n:View, key:String):Bool {
		n = valueOf(n);
		var val = rawValue(n, key);
		if (val == null) return false;
		if (Std.isOfType(val, Bool)) return val;
		return Std.string(val) == "true";
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
