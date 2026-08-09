package sui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Type;
import sys.io.File;
import sys.FileSystem;

/**
	Refuses, at compile time, a view the dynamic renderer cannot draw.

	## Why a check rather than a placeholder

	A node type the renderer has no branch for draws `?Picker` — which is the
	right answer for a tree that arrives as **data**, from a protocol nothing
	could have checked ahead of time. It is the wrong answer for a `body()`
	written here and compiled for a known renderer: that is a knowable defect,
	and treating a knowable defect as unknowable is how a blank panel reaches a
	developer with nothing to read.

	## Where the vocabulary comes from

	`runtime/DynamicView.swift`. The `switch` in it **is** the list of what can
	be drawn, so any list kept here would be a second copy of it — and it would
	drift in the direction that hurts: a case deleted from the Swift would still
	pass. Failing to read the file stops the build rather than approving
	everything, since an absence must not read as approval.

	## What is deliberately not judged

	Nodes with no rendering of their own, which `sui.nui.ViewSource` expands
	before any renderer sees them: a `ViewComponent` into its `body()`, a
	`ForEach` into siblings, a `ConditionalView` into the branch it selects.
	Demanding a branch for those would be asking the renderer for dead code.
**/
class DynamicCoverage {
	/** Expanded by the source, so never drawn — see `sui.nui.ViewSource`. **/
	static final EXPANDED = ["ForEach", "ConditionalView"];

	public static function register():Void {
		Context.onAfterTyping(check);
	}

	static function check(types:Array<ModuleType>):Void {
		var covered = coveredViewTypes();
		if (covered == null) return; // already reported

		var offenders:Array<{name:String, pos:haxe.macro.Expr.Position}> = [];
		for (mt in types) {
			switch (mt) {
				case TClassDecl(ref):
					var cls = ref.get();
					if (!buildsViews(cls)) continue;
					for (field in cls.fields.get()) collect(field, covered, offenders);
					for (field in cls.statics.get()) collect(field, covered, offenders);
				default:
			}
		}

		if (offenders.length == 0) return;

		var known = [for (k in covered.keys()) k];
		known.sort(Reflect.compare);

		for (i in 0...offenders.length) {
			var o = offenders[i];
			var msg = 'The dynamic renderer cannot draw "' + o.name + '".\n'
				+ '  Covered types: ' + known.join(", ") + '.\n'
				+ '  Add a case to the switch in sui/runtime/DynamicView.swift.';
			if (i == offenders.length - 1) Context.error(msg, o.pos);
			else Context.reportError(msg, o.pos);
		}
	}

	/**
		The types the Swift renderer switches on, read from its source.

		Only the `renderContent` switch: the file has others — modifier names,
		theme tokens, gradient anchors — and taking those too would approve a
		view type because a *modifier* happened to share its name.
	**/
	static function coveredViewTypes():Null<Map<String, Bool>> {
		var path = rendererPath();
		if (path == null) {
			Context.error('[SUI] runtime/DynamicView.swift not found: cannot tell what the dynamic renderer draws.',
				Context.currentPos());
			return null;
		}

		var source = try File.getContent(path) catch (_:Dynamic) null;
		if (source == null) {
			Context.error('[SUI] runtime/DynamicView.swift could not be read.', Context.currentPos());
			return null;
		}

		var start = source.indexOf("private func renderContent()");
		if (start < 0) {
			Context.error('[SUI] renderContent() not found in DynamicView.swift: the renderer\'s shape changed, and this check reads it.',
				Context.currentPos());
			return null;
		}
		// Bounded at the next function: `applyModifiers` holds a switch of its
		// own, over modifier names, and the file has more below that -- theme
		// tokens, gradient anchors, canvas ops. Reading past here approved a
		// view type because a *modifier* or a colour happened to share its name,
		// which is an absence reading as approval by another route.
		var end = source.indexOf("private func applyModifiers", start);
		if (end < 0) {
			Context.error('[SUI] applyModifiers() not found in DynamicView.swift: this check reads the renderer\'s shape, and it changed.',
				Context.currentPos());
			return null;
		}
		var body = source.substring(start, end);

		var covered = new Map<String, Bool>();
		var caseRe = ~/case[ \t]+((?:"[A-Za-z]+"[ \t]*,?[ \t]*)+):/;
		var nameRe = ~/"([A-Za-z]+)"/;
		var rest = body;
		while (caseRe.match(rest)) {
			var group = caseRe.matched(1);
			var names = group;
			while (nameRe.match(names)) {
				covered.set(nameRe.matched(1), true);
				names = nameRe.matchedRight();
			}
			rest = caseRe.matchedRight();
		}

		for (name in EXPANDED) covered.set(name, true);
		return covered;
	}

	/** The renderer shipped by the sui haxelib, wherever it is installed. **/
	static function rendererPath():Null<String> {
		try {
			var anchor = Context.resolvePath("sui/View.hx");
			var dir = haxe.io.Path.directory(haxe.io.Path.directory(anchor)); // .../src
			var candidate = haxe.io.Path.directory(dir) + "/runtime/DynamicView.swift";
			if (FileSystem.exists(candidate)) return candidate;
		} catch (_:Dynamic) {}
		return null;
	}

	/** An `App` or a `ViewComponent`: the classes that build views. **/
	static function buildsViews(cls:ClassType):Bool {
		var current = cls;
		while (current != null) {
			var name = current.pack.join(".") + (current.pack.length > 0 ? "." : "") + current.name;
			if (name == "sui.App" || name == "sui.ViewComponent") return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	static function collect(field:ClassField, covered:Map<String, Bool>,
			offenders:Array<{name:String, pos:haxe.macro.Expr.Position}>):Void {
		if (field.name != "body" && !returnsView(field)) return;
		var e = field.expr();
		if (e != null) walk(e, covered, offenders);
	}

	static function returnsView(field:ClassField):Bool {
		return switch (haxe.macro.TypeTools.follow(field.type)) {
			case TFun(_, ret): isView(ret);
			case _: false;
		};
	}

	static function isView(t:Type):Bool {
		return switch (haxe.macro.TypeTools.follow(t)) {
			case TInst(ref, _): extendsView(ref.get());
			case _: false;
		};
	}

	static function extendsView(cls:ClassType):Bool {
		var current = cls;
		while (current != null) {
			if (current.name == "View" && current.pack.join(".") == "sui") return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/**
		Whether the renderer draws this class, or a class it inherits from.

		The check is about the `viewType` a node carries, and a subclass carries
		its parent's unless it sets its own. `mui.ui.TextInput` extends
		`sui.ui.TextField` and reports `"TextField"` at runtime — judging it by
		its Haxe name refuses a type the renderer draws, and names a type nobody
		wrote. A class that renames itself sets `viewType`, and then nothing in
		the chain matches.
	**/
	static function coveredByChain(cls:ClassType, covered:Map<String, Bool>):Bool {
		var current = cls;
		while (current != null) {
			if (covered.exists(current.name)) return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	/**
		`sui.View` itself, which is not a node type.

		`App.body()` and `ViewComponent.body()` both return one before anything
		overrides them, so judging it would refuse every build over sui's own
		default bodies. The source turns a bare `View` into an empty stack, so it
		never reaches the renderer either.
	**/
	static function isBaseView(cls:ClassType):Bool {
		return cls.name == "View" && cls.pack.join(".") == "sui";
	}

	/** A composition unit, expanded rather than drawn. **/
	static function isComponent(cls:ClassType):Bool {
		var current = cls;
		while (current != null) {
			if (current.name == "ViewComponent" && current.pack.join(".") == "sui") return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	static function walk(e:TypedExpr, covered:Map<String, Bool>,
			offenders:Array<{name:String, pos:haxe.macro.Expr.Position}>):Void {
		if (e == null) return;

		switch (e.expr) {
			case TNew(ref, _, _):
				var cls = ref.get();
				// A user's own `class Badge extends View` is judged like any
				// other: restricting this to `sui.ui` would watch only our code
				// and leave a user's node to fail in silence, which is the
				// failure this check exists to remove.
				if (extendsView(cls) && !isComponent(cls) && !isBaseView(cls) && !coveredByChain(cls, covered)) {
					offenders.push({name: cls.name, pos: e.pos});
				}
			default:
		}

		haxe.macro.TypedExprTools.iter(e, function(sub) walk(sub, covered, offenders));
	}
}
#end
