# State & Actions

## @:state

`@:state` declares a reactive state variable. It generates a `@State var` in Swift.

```haxe
@:state var count:Int = 0;
@:state var name:String = "";
@:state var items:Array<TodoItem> = [];
```

No constructor initialization needed &mdash; the default value is specified inline.

### Supported Types

`@:state` validates the type at compile time. Only the following types are allowed:

| Type | Example | Valid? |
|------|---------|--------|
| `Int` | `@:state var x:Int = 0` | Yes |
| `Float` | `@:state var x:Float = 0.0` | Yes |
| `Bool` | `@:state var x:Bool = false` | Yes |
| `String` | `@:state var x:String = ""` | Yes |
| `Array<BasicType>` | `@:state var x:Array<String> = []` | Yes |
| `Array<Observable>` | `@:state var x:Array<TodoItem> = []` | Yes, if `TodoItem` extends `Observable` |
| Other classes | `@:state var x:MyClass` | Only if `MyClass` extends `Observable` |

Using an unsupported type (e.g. `@:state var x:Array<SomeClass>` where `SomeClass` doesn't extend `Observable`) produces a compile-time error:

```
[SwiftGen] State type SomeClass is not supported. Use a basic type (Int, Float, Bool, String),
an array of basic types, or a class extending Observable.
```

**Access:**

| Syntax | Description |
|--------|-------------|
| `.value` | Read the current value (Haxe side) |
| `.value = newValue` | Update the value and notify SwiftUI |

The variable name is used directly in action closures, `Text.bind` expressions, and binding references.

## Actions

An action is just a Haxe closure &mdash; `typedef StateAction = () -> Void`. You mutate
state by assigning to `.value`; the change is reflected in SwiftUI automatically.

```haxe
new Button("+", () -> count.value++)
new Button("-", () -> count.value--)
new Button("Reset", () -> count.value = 0)
new Button("Toggle", () -> isOn.value = !isOn.value)
```

A closure can run any Haxe logic and touch several state variables:

```haxe
new Button("Reset all", () -> {
    scale.value = 1;
    rotation.value = 0;
    offset.value = 0;
})
```

A bare function reference works too, as long as its signature is `() -> Void`:

```haxe
new Button("Login", MyApp.startLogin)
```

Actions run on a detached thread on the Haxe/C++ side. Each call site is registered
under a stable id at build time and dispatched from Swift &mdash; see
[The Bridge](../bridge.md) for the mechanics. Because every `@:state` property
mirrors SwiftUI's bindings back into Haxe via `didSet`, reading `someState.value`
inside an action always returns the current value, even one the user just typed into a
`TextField`.

### Bridge calls

To run business logic in Haxe/C++, just call the function from the closure and assign
its result. The closure already runs off the main thread, so a blocking call is fine:

```haxe
// Synchronous
new Button("Greet", () -> result.value = greet("World"))

// With a loading placeholder — both assignments are seen by SwiftUI
new Button("Fetch", () -> {
    result.value = "Loading...";
    result.value = fetchUrl("https://example.com");
})

// Fire-and-forget (no return value)
new Button("Refresh", () -> refresh())
```

> [!TIP]
> Periodic work that used to be expressed as an interval action now lives on the view:
> `view.every(2.0, () -> tick.value++)` ticks the closure every two seconds.

### Migrating from the `StateAction` enum

The `StateAction` enum, the fluent shortcuts (`.inc`, `.dec`, `.setTo`, `.tog`,
`.appendAction`), the `.animated()` wrapper and the `Action` abstract have all been
removed. Every action is now a plain `() -> Void` closure.

| Old API | New closure |
|---------|-------------|
| `count.inc(1)` / `StateAction.Increment(count, 1)` | `() -> count.value++` |
| `count.dec(1)` / `StateAction.Decrement(count, 1)` | `() -> count.value--` |
| `x.setTo(v)` / `StateAction.SetValue(x, v)` | `() -> x.value = v` |
| `b.tog()` / `StateAction.Toggle(b)` | `() -> b.value = !b.value` |
| `items.appendAction(v)` | `() -> items.value = items.value.concat([v])` |
| `StateAction.RunExpr(expr)` | `() -> expr` |
| `StateAction.CustomSwift("…")` | rewrite the logic in pure Haxe inside the closure |
| `StateAction.BridgeCall(s, "fn", a)` | `() -> s.value = fn(a)` |
| `StateAction.BridgeCallLoading(s, "…", "fn", a)` | `() -> { s.value = "…"; s.value = fn(a); }` |
| `StateAction.BridgeCallVoid("fn", a)` | `() -> fn(a)` |
| `StateAction.Animated(action, curve)` | closure + `.animation(curve, state)` on the view |
| `StateAction.IntervalLoop(secs, action)` | `view.every(secs, () -> …)` |

The `CustomSwift` escape hatch for actions is gone &mdash; write the equivalent logic in
Haxe. To make animations follow a mutation, declare which state drives a view's
animation with `.animation(AnimationCurve.X, state)`; see [Animations](../animations.md).

## Text.bind

Displays state values in text. Pass any String-typed Haxe expression — sui's macro walks the typed AST and emits Swift string interpolation directly:

```haxe
Text.bind('Count: ${count.value}')           // → Text("Count: \(count)")
Text.bind(name.value)                         // → Text("\(name)")
Text.bind('${rating} / 5')                    // → Text("\(rating) / 5")  (component @:swiftBinding field — no .value)
Text.bind(todos.value[i].title)               // → Text("\(todos[i].title)")  (inside ForEach.byIndex)
```

Use single-quoted Haxe strings for `${...}` interpolation. For `State<T>` references, read `.value`; for component `@:swiftBinding` fields, reference the field bare.

### Legacy: Text.withState

`Text.withState("{name}")` is kept for backward compatibility. New code should prefer `Text.bind`, which lets the Haxe compiler typecheck the expression before sui rewrites it to Swift.

## Putting It Together

```haxe
class CounterApp extends App {
    @:state var count:Int = 0;

    public function new() {
        super();
        appName = "Counter";
        bundleIdentifier = "com.example.counter";
    }

    override function body():View {
        return new VStack([
            Text.bind('Count: ${count.value}')
                .font(FontStyle.Title)
                .padding(),
            new HStack(null, 20, [
                new Button("-", () -> count.value--),
                new Button("+", () -> count.value++)
            ])
        ]);
    }
}
```

Each button's closure mutates `count.value`; SwiftUI re-renders the `Text.bind` automatically.
