package sui.state;

/**
    Runtime store for action closures, dispatched from Swift through
    the C bridge by integer handle.

    Two families:

    - **Plain handlers** — closures attached outside any `ForEach` row
      template. `StateMacro` rewrites every action call site to
      `Callbacks.reg(<id>, <closure>)`, so registration happens when
      the view tree is built (`body()` / `commands()` / `settings()`
      run once at boot) and the Swift side dispatches
      `HaxeBridgeC.invokeAction(<id>)` with the same compile-time id.
      No parallel counters: the id is assigned once, by the macro,
      and travels both ways through the typed AST.

    - **Indexed builders** — closures written inside a `ForEach` row
      template. The row template never executes at runtime (SwiftUI
      iterates on the Swift side), so the macro lifts the closure
      into a static *builder* `(i0, i1) -> (() -> Void)` on the App
      class that re-materialises the iteration values from the row
      indices. The builder is registered here from the App
      constructor, and the Swift tap site dispatches
      `HaxeBridgeC.invokeIndexedAction(<id>, i0, i1)` with the live
      SwiftUI loop indices (outermost first, `-1` for unused slots).

    hxcpp note: both maps are static fields, i.e. GC roots. The
    Swift side only ever holds plain `Int` handles — never a Haxe
    object — because Swift closure captures are invisible to the
    hxcpp GC: a `Dynamic` captured by an ARC closure could be
    collected (or moved) between row build and tap. Routing every
    dispatch through this store sidesteps that entirely.
**/
@:keep // `run` / `runIndexed` are only called from the generated C bridge
class Callbacks {
    static var _handlers:Map<Int, () -> Void> = new Map();
    static var _indexed:Map<Int, (Int, Int) -> (() -> Void)> = new Map();

    /** Register `h` under the compile-time id assigned by StateMacro
        and return it unchanged — the wrapper is transparent at the
        call site. **/
    public static function reg(id:Int, h:() -> Void):() -> Void {
        if (h != null) _handlers.set(id, h);
        return h;
    }

    /** Invoke a registered handler. Called from the C bridge
        (`haxe_bridge_invoke_action`). **/
    public static function run(id:Int):Void {
        var h = _handlers.get(id);
        if (h != null) h();
    }

    /** Call-site marker for an action closure inside a `ForEach` row
        template. The row template never executes at runtime, so the
        returned closure is inert; the Swift side dispatches through
        `runIndexed` with the live loop indices instead. `frames` is
        the number of enclosing ForEach levels the lifted builder
        re-materialises — the Swift generator passes that many loop
        indices, innermost-last. **/
    public static function indexed(id:Int, frames:Int):() -> Void {
        return function() {};
    }

    /** Register an indexed builder (synthesised by StateMacro,
        called from the App constructor). **/
    public static function registerIndexed(id:Int, b:(Int, Int) -> (() -> Void)):Void {
        _indexed.set(id, b);
    }

    /** Build + run an indexed handler. Called from the C bridge
        (`haxe_bridge_invoke_indexed_action`) with the SwiftUI loop
        indices, outermost first; unused slots are `-1`. **/
    public static function runIndexed(id:Int, i0:Int, i1:Int):Void {
        var b = _indexed.get(id);
        if (b != null) b(i0, i1)();
    }
}
