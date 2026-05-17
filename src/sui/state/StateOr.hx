package sui.state;

/**
    A value that is either a static `Float` or a reactive `State<Float>`.
    Used by visual effect modifiers to accept both static and state-bound values.

    ```haxe
    .scaleEffect(1.5)     // static — always 1.5
    .scaleEffect(scale)   // state — animates when scale changes
    ```
**/
abstract StateOr<T>(Dynamic) {
    @:from public static inline function fromFloat(v:Float):StateOr<Float> {
        return cast v;
    }

    @:from public static inline function fromInt(v:Int):StateOr<Float> {
        return cast v;
    }

    @:from public static inline function fromState<T>(s:State<T>):StateOr<T> {
        return cast s;
    }

    /** Legacy stringly-typed escape hatch — accepts an expression
        the macro forwards into Swift verbatim (e.g.
        `"dayEventStartFracs[i]"` to subscript an array state by the
        enclosing `ForEach` index). Prefer the typed `State<T>` form
        when the binding doesn't need an index. **/
    @:from public static inline function fromString(s:String):StateOr<Float> {
        return cast s;
    }
}
