package sui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using haxe.macro.ExprTools;
#end

/**
	Defers a view's *values* so they are read when the renderer asks, not when
	`body()` ran.

	## The problem it solves

	`new Text("count: " + n.get())` computes its string during `body()`. The
	string is then baked into the node, so the only way to show a new one is to
	run `body()` again and rebuild the whole tree — which is what a state write
	used to do, for a label changing by one character.

	The value has to be a **thunk** rather than a result. Then the read happens
	when the node is asked for its value, which is inside the SwiftUI view that
	displays it, and only that view has to be told to ask again.

	## The rewrite

	On the dynamic path, inside `body()` and any method declared to return a
	`View`:

	```haxe
	new Text("count: " + n.get())
	```

	becomes

	```haxe
	{ var __live = new Text(""); __live.liveBuild = () -> new Text("count: " + n.get()); __live; }
	```

	The node is built with **neutral values**, so constructing it reads no state
	at all; `liveBuild` carries the real expression, and `sui.nui.ViewSource`
	calls it when a value is asked for.

	## Why it is what makes fine grain possible here

	Deferring is not an optimisation on its own — it is what separates the two
	kinds of state a tree depends on. What is still read *during* `body()` after
	this rewrite is exactly what decides the tree's **shape**: a `ForEach`'s
	list, a `ConditionalView`'s condition. Everything else has moved into a
	thunk, where it belongs to one node. `sui.runtime.ReadScope` reads that
	split off the two evaluations.

	## What it deliberately does not touch

	- **Containers.** If any argument is a `View` or an array of them, the node
	  is left alone: re-running its constructor would rebuild its children and
	  throw away their identity.
	- **Non-value arguments.** A binding name, a closure, a `State<T>` — these
	  are identities, not values. They stay on the initial node, which is what
	  the controls and the action path read.
	- **Constants.** `new Text("hello")` has nothing to defer, so it is untouched.

	Nothing is rewritten unless at least one value argument was actually deferred.
**/
class LiveProps {
	#if macro
	/** Value types worth deferring: what a view *displays*. **/
	static function isDeferrableValue(t:Type):Bool {
		return switch (Context.follow(t)) {
			case TInst(ref, _): ref.get().name == "String";
			case TAbstract(ref, _):
				switch (ref.get().name) {
					case "Int" | "Float" | "Bool": true;
					case _: false;
				}
			case _: false;
		};
	}

	/** A view, or a collection of them: the sign of a container. **/
	static function isViewish(t:Type):Bool {
		return switch (Context.follow(t)) {
			case TInst(ref, params):
				var cls = ref.get();
				if (cls.name == "Array" && params.length > 0) return isViewish(params[0]);
				var c = cls;
				while (c != null) {
					if (c.name == "View" && c.pack.join(".") == "sui") return true;
					c = c.superClass == null ? null : c.superClass.t.get();
				}
				false;
			case _: false;
		};
	}

	static function neutralFor(t:Type):Expr {
		return switch (Context.follow(t)) {
			case TInst(ref, _) if (ref.get().name == "String"): macro "";
			case TAbstract(ref, _):
				switch (ref.get().name) {
					case "Int": macro 0;
					case "Float": macro 0.0;
					case "Bool": macro false;
					case _: macro null;
				}
			case _: macro null;
		};
	}

	/** Is this expression already a constant? Then there is nothing to defer. **/
	static function isConstant(e:Expr):Bool {
		return switch (e.expr) {
			// A single-quoted string is not a constant until the compiler has
			// looked inside it: Haxe keeps `'n = ${count.get()}'` as a CString
			// through the build pass, interpolation and all. Calling that
			// constant deferred nothing, so the read stayed in body() -- which
			// made the cell structural, so every write rebuilt the tree and the
			// whole screen flickered for a label changing by one digit.
			case EConst(CString(value, kind)):
				kind != SingleQuotes || value.indexOf("$") < 0;
			case EConst(CInt(_) | CFloat(_)): true;
			case EConst(CIdent("true" | "false" | "null")): true;
			case _: false;
		};
	}

	/** The constructor's parameter types, or null if they cannot be resolved. **/
	static function ctorArgTypes(tp:TypePath, pos:Position):Null<Array<Type>> {
		try {
			var t = Context.resolveType(TPath(tp), pos);
			switch (Context.follow(t)) {
				case TInst(ref, _):
					var cls = ref.get();
					// A sui view, or something that extends one. Restricting this to
					// the `sui.ui` package meant a framework layered on top got no
					// deferral at all: `mui.ui.Text` is a `sui.ui.Text`, but it is
					// not *in* sui.ui, so every value stayed computed during body()
					// -- which made every cell structural, so every write rebuilt
					// the tree and the app lost its fine grain entirely.
					if (!isSuiView(cls)) return null;
					var ctor = cls.constructor;
					if (ctor == null) return null;
					switch (Context.follow(ctor.get().type)) {
						case TFun(args, _): return [for (a in args) a.t];
						case _: return null;
					}
				case _: return null;
			}
		} catch (_:Dynamic) {
			return null;
		}
	}

	/** A view sui ships, or a subclass of one. **/
	static function isSuiView(cls:haxe.macro.Type.ClassType):Bool {
		var current = cls;
		while (current != null) {
			if (current.pack.join(".") == "sui.ui") return true;
			current = current.superClass == null ? null : current.superClass.t.get();
		}
		return false;
	}

	static function rewrite(e:Expr):Expr {
		return switch (e.expr) {
			case ENew(tp, args) if (args.length > 0):
				var types = ctorArgTypes(tp, e.pos);
				if (types == null || types.length < args.length) {
					e.map(rewrite);
				} else {
					// A container keeps its identity: never re-run its constructor.
					var container = false;
					for (t in types) if (isViewish(t)) container = true;
					if (container) {
						e.map(rewrite);
					} else {
						var neutral = [];
						var deferred = false;
						for (i in 0...args.length) {
							if (isDeferrableValue(types[i]) && !isConstant(args[i])) {
								neutral.push(neutralFor(types[i]));
								deferred = true;
							} else {
								neutral.push(args[i]);
							}
						}
						if (!deferred) {
							e.map(rewrite);
						} else {
							var placeholder = {expr: ENew(tp, neutral), pos: e.pos};
							macro @:pos(e.pos) {
								var __live = $placeholder;
								__live.liveBuild = function() return $e;
								__live;
							};
						}
					}
				}
			case _:
				e.map(rewrite);
		};
	}

	/** Rewrite `body()` and every method declared to return a `View`. **/
	public static function apply(fields:Array<Field>):Array<Field> {
		// Nothing to defer on the static path: the transpiler reads `body()`
		// from the typed AST, and a thunk is exactly what it cannot translate.
		if (RenderPath.isStatic()) return fields;

		for (field in fields) {
			switch (field.kind) {
				case FFun(fn) if (fn.expr != null):
					if (field.name != "body" && !returnsView(fn.ret)) continue;
					fn.expr = rewrite(fn.expr);
				case _:
			}
		}
		return fields;
	}

	static function returnsView(ret:Null<ComplexType>):Bool {
		return switch (ret) {
			case TPath(p): p.name == "View";
			case _: false;
		};
	}
	#end
}
