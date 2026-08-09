import sui.View;
import sui.nui.ViewSource;
import sui.runtime.ViewNodeBridge;
import sui.state.State;
import sui.ui.Button;
import sui.ui.ConditionalView;
import sui.ui.ForEach;
import sui.ui.HStack;
import sui.ui.Text;
import sui.ui.VStack;

/**
	Checks the Haxe half of sui's dynamic renderer.

	## Why this exists

	`sui.nui.ViewSource` is reached from **Swift**, through a C bridge, by
	symbol. No Haxe compiler sees the way it is used, and the failure mode is
	not a crash: a node the walk describes wrongly draws something slightly
	wrong, or nothing at all, with no diagnostic anywhere.

	What it mostly checks is the set of nodes that have **no rendering of their
	own**. sui was written for a transpiler, which read a `ViewComponent`, a
	`ForEach` and a `ConditionalView` at compile time and emitted Swift for
	them. A walker cannot read them at compile time; unless they are expanded
	here they reach the renderer as node types nothing draws.

	Run with `tests/run_dynamic.sh`. Nothing native is involved — the walk is
	plain Haxe, so it runs under `--interp`.
**/
class NuiCheck {
	static var failures = 0;

	/** The text a node shows, read through the source that describes it.

		Not through `ViewNodeBridge`: its `reader()` keeps one source until the
		next `rebuild()`, so two checks against the same node would share one
		generation's memo. The app replaces the source on every rebuild; a test
		that walks several trees by hand must say which one it is asking. **/
	static function textOf(src:ViewSource, n:View):String {
		var resolved = src.resolveWalked(n);
		if (resolved == null) return "";
		var content:Dynamic = Reflect.field(resolved, "content");
		return content != null ? Std.string(content) : "";
	}

	static function check(what:String, ok:Bool, ?detail:String):Void {
		if (ok) {
			Sys.println('  ok   $what');
		} else {
			failures++;
			Sys.println('  FAIL $what' + (detail == null ? "" : '  -- $detail'));
		}
	}

	static function main() {
		Sys.println("sui — nui pull contract");

		// --- the plain walk ---
		var root:View = new VStack(null, 8, [new Text("a"), new Button("b", () -> {})]);
		var src = new ViewSource(root);
		check("the type is the bare name", src.typeOf(root) == "VStack", src.typeOf(root));
		check("children are counted", src.childCount(root) == 2, Std.string(src.childCount(root)));
		check("a child is reachable", src.typeOf(src.childAt(root, 1)) == "Button");

		// --- a component is described by what it renders ---
		//
		// The transpiler emitted a Swift struct per ViewComponent. A walker has
		// no struct to reach for: left alone the component arrives as its own
		// class name, which no renderer switches on.
		var comp:View = new Card("hello");
		var cs = new ViewSource(comp);
		check("a component reports the type it expands to", cs.typeOf(comp) == "VStack", cs.typeOf(comp));
		check("and its content is reachable through it", cs.childCount(comp) == 1,
			Std.string(cs.childCount(comp)));

		var hosting:View = new VStack(null, null, [new Card("nested")]);
		var hs = new ViewSource(hosting);
		check("a component nested in a tree is expanded too",
			hs.typeOf(hs.childAt(hosting, 0)) == "VStack");

		// A component that never overrode body() gets the base
		// `ViewComponent.body()`, which returns a bare `sui.View`. That is a
		// component with nothing in it, not a node to draw -- and `View` is a
		// type the renderer has no branch for, so it would have gone to the
		// unknown-type case for what is really an empty body.
		var hollow:View = new Bare();
		var es = new ViewSource(hollow);
		check("a component with no body of its own draws an empty stack",
			es.typeOf(hollow) == "VStack" && es.childCount(hollow) == 0, es.typeOf(hollow));

		// --- a loop yields siblings ---
		var items = new State<Array<String>>(["red", "green"], "items");
		var loop:View = new VStack(null, null, [
			new Text("head"),
			new ForEach(items, (c:String) -> new Text("item: " + c)),
			new Text("tail")
		]);
		var ls = new ViewSource(loop);
		check("a ForEach yields siblings, not a node of its own",
			ls.childCount(loop) == 4, Std.string(ls.childCount(loop)));
		check("the items keep their place among the siblings",
			ls.typeOf(ls.childAt(loop, 1)) == "Text"
			&& textOf(ls, ls.childAt(loop, 1)) == "item: red"
			&& textOf(ls, ls.childAt(loop, 3)) == "tail",
			textOf(ls, ls.childAt(loop, 1)));

		// byIndex hands the lambda the position, not the element.
		var byIdx:View = new VStack(null, null, [ForEach.byIndex(items, i -> new Text("#" + i))]);
		var bis = new ViewSource(byIdx);
		check("ForEach.byIndex iterates positions",
			bis.childCount(byIdx) == 2 && textOf(bis, bis.childAt(byIdx, 0)) == "#0",
			textOf(bis, bis.childAt(byIdx, 0)));

		// The legacy form's body is a string template the transpiler resolved
		// against the generated appState. There is nothing to call at runtime,
		// so the walk must not invent items -- it is refused at compile time.
		var legacy:View = new VStack(null, null, [new ForEach(items, "i", new Text("{items[i]}"))]);
		var lgs = new ViewSource(legacy);
		check("the legacy string-template ForEach yields nothing to run",
			lgs.typeOf(lgs.childAt(legacy, 0)) == "ForEach",
			lgs.typeOf(lgs.childAt(legacy, 0)));

		// Reading twice must not build the items twice.
		var built = 0;
		var counted:View = new VStack(null, null, [
			new ForEach(items, function(c:String) {
				built++;
				return new Text(c);
			})
		]);
		var ks = new ViewSource(counted);
		ks.childCount(counted);
		ks.childAt(counted, 0);
		ks.childAt(counted, 1);
		check("the items are built once per generation", built == 2, Std.string(built));

		// A source describes one generation; the next one reads the list again.
		items.set(["red", "green", "blue"]);
		var next = new ViewSource(loop);
		check("a write to the list is seen by the next generation",
			next.childCount(loop) == 5, Std.string(next.childCount(loop)));

		// Where one view is expected there are no siblings to become.
		var bare:View = new ForEach(items, (c:String) -> new Text(c));
		var bs = new ViewSource(bare);
		check("a ForEach standing alone becomes a stack of its items",
			bs.typeOf(bare) == "VStack" && bs.childCount(bare) == 3,
			bs.typeOf(bare) + "/" + bs.childCount(bare));

		// --- a condition is read, not described ---
		//
		// The transpiler emitted `if appState.flag { … } else { … }`. The tree
		// is rebuilt on every state change here, so the branch can simply be
		// chosen -- and the renderer never learns what an `if` is.
		var flag = new State<Bool>(true, "flag");
		var cond:View = new ConditionalView(flag, new Text("yes"), new Text("no"));
		var cds = new ViewSource(cond);
		check("a true condition resolves to its then-branch",
			cds.typeOf(cond) == "Text" && textOf(cds, cond) == "yes",
			textOf(cds, cond));

		flag.set(false);
		var cds2 = new ViewSource(cond);
		check("a false condition resolves to its else-branch",
			textOf(cds2, cond) == "no", textOf(cds2, cond));

		var noElse:View = new ConditionalView(new State<Bool>(false, "off"), new Text("yes"));
		var nes = new ViewSource(noElse);
		check("a false condition with no else-branch draws an empty stack",
			nes.typeOf(noElse) == "VStack" && nes.childCount(noElse) == 0,
			nes.typeOf(noElse));

		// The string form named a field on the generated appState. At runtime it
		// is a name with nothing to look it up in -- guessing a branch would
		// draw the wrong half of the screen, so neither is taken.
		var stringly:View = new ConditionalView("isLoggedIn", new Text("in"), new Text("out"));
		var ss = new ViewSource(stringly);
		check("a stringly condition takes neither branch",
			ss.typeOf(stringly) == "VStack" && ss.childCount(stringly) == 0,
			ss.typeOf(stringly));

		// --- through the bridge, the way Swift asks ---
		//
		// Swift holds the node it was handed by `viewnode_get_child` and asks it
		// for text. Reading the raw field there returned "" for anything that
		// expands, so the accessors resolve first; this is that path end to end.
		ViewNodeBridge.setApp(new Host());
		var hostRoot = ViewNodeBridge.getRoot();
		check("the bridge walks an app's tree", ViewNodeBridge.getViewType(hostRoot) == "VStack",
			ViewNodeBridge.getViewType(hostRoot));
		var first = ViewNodeBridge.getChild(hostRoot, 0);
		check("and reads the text of a component through it",
			ViewNodeBridge.getTextContent(ViewNodeBridge.getChild(first, 0)) == "carded",
			ViewNodeBridge.getTextContent(ViewNodeBridge.getChild(first, 0)));

		Sys.println(failures == 0 ? "\nall good" : '\n$failures failed');
		Sys.exit(failures == 0 ? 0 : 1);
	}
}

/** A component: no rendering of its own, expanded into what body() returns. **/
class Card extends sui.ViewComponent {
	public var title:String;

	public function new(title:String) {
		super();
		this.title = title;
	}

	override public function body():View {
		return new VStack(null, null, [new Text(title)]);
	}
}

/** A component that never overrode body(); the base returns `this`. **/
class Bare extends sui.ViewComponent {
	public function new() {
		super();
		this.viewType = "Bare";
	}
}

/** An app whose body() holds a component, walked through the bridge. **/
class Host extends sui.App {
	public function new() {
		super();
		appName = "Host";
	}

	override public function body():View {
		return new VStack(null, null, [new Card("carded")]);
	}
}
