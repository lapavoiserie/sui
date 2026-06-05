package sui.state;

/**
    A state action is a plain Haxe closure. Write whatever you need —
    multi-statement bodies, captures, partial application, calls into
    your own code — and the framework runs it through the bridge when
    the user interacts:

    ```haxe
    new Button("+", () -> count.value++)
    new Button("Reset", () -> count.value = 0)
    new Button("Login", MyApp.startLogin)
    view.onTapGesture(() -> isDark.value = !isDark.value)
    view.onTapGesture(() -> { flag.value = true; doWork(); })
    ```

    Typed setters (`count.value = …`) go through the `State<T>`
    property setter, which notifies the SwiftUI side — no dispatch
    enum, no `Reflect`.

    Historical note: this used to be an enum with declarative
    variants (`Increment`, `SetValue`, `Toggle`, `BridgeCall`,
    `RunExpr`, …) that the Swift generator pattern-matched into
    Swift fragments. All of that is now expressed directly in Haxe:

    - `count.inc(1)`            → `() -> count.value++`
    - `x.setTo(v)`              → `() -> x.value = v`
    - `b.tog()`                 → `() -> b.value = !b.value`
    - `RunExpr(expr)`           → `() -> expr`
    - `BridgeCall(s, "fn", a)`  → `() -> s.value = fn(a)`
    - `BridgeCallLoading(s, l, "fn", a)`
                                → `() -> { s.value = l; s.value = fn(a); }`
    - `BridgeCallVoid("fn", a)` → `() -> fn(a)`
    - `Animated(action, curve)` → closure + `.animation(curve, state)`
                                  on the view (SwiftUI-idiomatic)
    - `IntervalLoop(s, action)` → `.every(s, () -> …)` on the view
**/
typedef StateAction = () -> Void;
