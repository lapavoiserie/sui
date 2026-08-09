package sui.macros;

#if macro
import haxe.macro.Context;
#end

/**
	Which of the two renderers a build targets — asked here, and nowhere else.

	`sui` has always had two ways to put a view on screen:

	- **dynamic** — the app runs, `body()` builds a tree, and `DynamicView.swift`
	  walks it through `nui`'s pull contract. A state write rebuilds the tree,
	  and the host redraws from it.
	- **static** — `SwiftGenerator` reads `body()` from the typed AST at compile
	  time and emits SwiftUI ahead of time. Nothing of the view survives to
	  runtime.

	The static path used to be the default and the dynamic one the opt-in
	(`-D sui_hot_reload`, set by `sui build --watch`). That is now inverted:
	**dynamic is the path**, and the transpiler is kept, unmaintained, behind
	`-D sui_static` so a build that depended on it still has somewhere to go.

	## Why it was set aside rather than kept in parallel

	Not because emitting SwiftUI ahead of time is a bad idea. Until recently it
	was the *only* way sui could be reactive at all: SwiftUI records no
	dependency on a state read through a C bridge, so a dynamic build drew its
	first frame and then froze. That argument is spent — the renderer observes
	the app's own state writes now and rebuilds from them — and what is left is
	a transpiler that has to translate arbitrary Haxe to stay correct, against a
	renderer that simply runs it.

	## What it costs, stated rather than discovered

	The dynamic path rebuilds the **whole tree** on a state write, where the
	generated SwiftUI got a real `@Binding` and updated one view. Rebuilds are
	coalesced to one per turn of the run loop, which makes a burst cheap and a
	very large tree still the thing to watch. If that shows up in a profile,
	`-D sui_static` is why it is still here.
**/
class RenderPath {
	/** Opt back in to the decommissioned static transpiler. **/
	public static inline var STATIC_DEFINE = "sui_static";

	/** What `sui build --watch` used to pass. A no-op now: the default says it. **/
	public static inline var DYNAMIC_DEFINE = "sui_hot_reload";

	#if macro
	static var _isStatic:Null<Bool> = null;

	/** True when this build asked for the decommissioned static transpiler. **/
	public static function isStatic():Bool {
		if (_isStatic == null) _isStatic = resolve();
		return _isStatic;
	}

	/** True for every build that did not. **/
	public static function isDynamic():Bool {
		return !isStatic();
	}

	/**
		Resolved once. The deprecation warning belongs to the build, not to each
		of the places that branch on the answer.
	**/
	static function resolve():Bool {
		if (!Context.defined(STATIC_DEFINE)) return false;

		// Both defines at once is not a preference to guess at: one of them is
		// left over, and picking either silently would build something the
		// developer did not ask for.
		if (Context.defined(DYNAMIC_DEFINE)) {
			Context.error('[SUI] -D $STATIC_DEFINE and -D $DYNAMIC_DEFINE contradict each other.\n'
				+ '  Drop -D $STATIC_DEFINE for the dynamic renderer, which is the default,\n'
				+ '  or drop -D $DYNAMIC_DEFINE if the static path is really what you want.',
				Context.currentPos());
		}

		Context.warning('[SUI] the static SwiftUI path is decommissioned and unmaintained.\n'
			+ '  It translates a subset of Haxe, and a view type it cannot translate\n'
			+ '  reaches Swift as a name that does not compile.\n'
			+ '  Drop -D $STATIC_DEFINE to use the dynamic renderer.',
			Context.currentPos());
		return true;
	}
	#end
}
