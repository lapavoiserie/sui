package sui.state;

/**
    Describes a state mutation declaratively so the Swift generator
    can emit proper SwiftUI code instead of trying to decompile closures.

    State references are type-checked — pass the `State<T>` field directly:
    ```haxe
    StateAction.Increment(rotation, 90)    // not "rotation"
    StateAction.Toggle(showDetail)          // not "showDetail"
    ```
**/
enum StateAction {
    /** Increment a state variable by a value. **/
    Increment(state:Dynamic, amount:Int);

    /** Decrement a state variable by a value. **/
    Decrement(state:Dynamic, amount:Int);

    /** Set a state variable to a specific value. **/
    SetValue(state:Dynamic, value:Dynamic);

    /** Toggle a boolean state variable. **/
    Toggle(state:Dynamic);

    /** Append to an array state variable. **/
    Append(state:Dynamic, value:Dynamic);

    /** Custom Swift expression (escape hatch).

        **Discouraged** for new code — every other variant of this
        enum (`Increment`, `SetValue`, `Toggle`, `Append`, `RunExpr`,
        `BridgeCall*`, `Animated`, `IntervalLoop`) is type-checked
        at the Haxe layer and emits Swift directly via
        `qualifyStateName`. `CustomSwift` is the only path that
        still relies on the legacy `rewriteStateRefsToAppState`
        text rewriter to prefix `appState.` on bare state names in
        the raw Swift string.

        Prefer `RunExpr(...)` for arbitrary side effects, or one of
        the typed mutation variants for simple cases.

        Also used internally as the transport for `RunExpr` sentinel
        strings (`StateMacro.synthesiseRunExpr` encodes the bridge
        target as a `CustomSwift(sentinel)` payload that the Swift
        codegen recognises). No `@:deprecated` annotation here so
        that internal use compiles warning-free. **/
    CustomSwift(code:String);

    /**
        Run a Haxe expression for its side effects. The macro
        captures the expression at build time, synthesises an
        `@:expose static` wrapper on the App class, and the Swift
        codegen routes the action into
        `Task.detached { _ = HaxeBridgeC.<wrapper>(args) }`.

        Lambda parameters in scope (e.g. `i` from an enclosing
        `ForEach`) are passed through automatically. State refs
        are qualified to `App.instance.<name>` so the static
        wrapper can read them.

        ```haxe
        view.onTapGesture(StateAction.RunExpr(
            App.toggleCalendar(Std.string(i))
        ));
        ```

        Strictly preferable to `CustomSwift` whenever the action
        is pure Haxe — type-checked, refactor-safe, and no Swift
        mixed into a string.
    **/
    RunExpr(expr:Dynamic);

    /**
        Call a @:expose function asynchronously and assign the result to a state variable.

        ```haxe
        BridgeCall(result, "greet", "World")
        BridgeCall(result, "doLogin", ["url", "email", "pass"])
        ```
    **/
    BridgeCall(state:Dynamic, functionName:String, args:Dynamic);

    /**
        Like BridgeCall but sets a loading value immediately before the async call.

        ```haxe
        BridgeCallLoading(result, "Loading...", "fetchData", "https://url")
        ```
    **/
    BridgeCallLoading(state:Dynamic, loadingValue:String, functionName:String, args:Dynamic);

    /**
        Call a `@:expose` function asynchronously and discard the
        result. Use this for periodic ticks and other fire-and-forget
        bridge calls where you don't want the return value to clobber
        a state field.

        ```haxe
        BridgeCallVoid("tickNowLine", "")
        ```
    **/
    BridgeCallVoid(functionName:String, args:Dynamic);

    /**
        Wrap any StateAction in a SwiftUI `withAnimation` block.

        ```haxe
        StateAction.Animated(rotation.inc(90), AnimationCurve.Spring)
        ```

        Generates:
        ```swift
        withAnimation(.spring) { rotation += 90 }
        ```
    **/
    Animated(action:StateAction, curve:AnimationCurve);

    /**
        Run `action` every `seconds` for as long as the view stays
        attached. Used with `.taskAction(...)` for periodic refreshes
        that don't depend on a user gesture (e.g. a clock indicator,
        live data polling).

        ```haxe
        myView.taskAction(
            StateAction.IntervalLoop(60, StateAction.BridgeCall(_, "tick", ""))
        )
        ```

        Generates a `Task.sleep(_:)` loop guarded by `Task.isCancelled`
        so the loop terminates when the view disappears.
    **/
    IntervalLoop(seconds:Float, action:StateAction);
}
