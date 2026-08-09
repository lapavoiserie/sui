package sui.runtime;

/**
	Records which state cells an expression read, by name.

	## Why sui needs this and `aui` does not

	Compose's snapshot system records a read of a `MutableState` at any stack
	depth, including through the JVM frames Haxe emits — so `aui` gets
	fine-grained recomposition without anyone tracking anything.

	SwiftUI has no equivalent. A read that happens through a C bridge is
	invisible to it: it cannot know that *this* `Text` depends on *that* cell.
	So the dependency has to be observed on the Haxe side and handed over. That
	is all this is — a scope you evaluate something inside, which afterwards
	tells you what it touched.

	## The two tiers it serves

	- Evaluating **`body()`** inside a scope yields the cells that shape the
	  *tree*: a `ForEach`'s list, a `ConditionalView`'s condition. A write to one
	  of those has to rebuild, because the shape changed.
	- Evaluating a node's **deferred value** inside a scope yields the cells that
	  one node displays. A write to one of those touches that node, and nothing
	  else.

	The split falls out on its own once values are deferred into thunks: what is
	left reading inside `body()` is exactly what decides the shape.

	## Deliberately not `rui.Signal`'s effect stack

	`Effect` already tracks reads, and would answer with the `Signal`s
	themselves. What crosses to Swift is a **name**: the renderer keys its
	mirrors by the same name a control binds to, and there is no way back from a
	signal to the cell that owns it. So the note is taken one level up, where the
	name is still in hand.
**/
class ReadScope {
	static var _stack:Array<Map<String, Bool>> = [];

	/** Start recording. Scopes nest: an inner one does not hide from an outer. **/
	public static function begin():Void {
		_stack.push(new Map());
	}

	/** Stop recording, and return the names read since the matching `begin`. **/
	public static function end():Array<String> {
		if (_stack.length == 0) return [];
		var frame = _stack.pop();
		var names = [for (name in frame.keys()) name];
		names.sort(Compare.strings);
		// A read inside a nested scope is a read in every scope around it: a
		// value the whole tree depends on is not less of a dependency because
		// something narrower also asked for it.
		if (_stack.length > 0) {
			var outer = _stack[_stack.length - 1];
			for (name in names) outer.set(name, true);
		}
		return names;
	}

	/** Note a read. Free when nothing is recording, which is the common case. **/
	public static inline function note(name:String):Void {
		if (_stack.length > 0 && name != null && name != "") {
			_stack[_stack.length - 1].set(name, true);
		}
	}

	/** Whether anything is recording — for a caller that can skip work. **/
	public static inline function recording():Bool {
		return _stack.length > 0;
	}

	/**
		Abandon every open scope.

		`body()` can throw, and a scope left open would silently attribute the
		next tree's reads to the failed one. The bridge calls this before
		starting a generation rather than trusting the last one to have unwound.
	**/
	public static function reset():Void {
		_stack = [];
	}
}

private class Compare {
	public static function strings(a:String, b:String):Int {
		return a < b ? -1 : (a > b ? 1 : 0);
	}
}
