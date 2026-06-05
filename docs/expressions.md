# Typed Expressions

sui's macro reads the typed Haxe AST of every modifier argument, `Text.bind(...)` body, and `ForEach.byIndex` lambda — then emits the matching Swift expression directly. No template strings, no text rewriter, every reference is type-checked at compile time.

This page documents *which* Haxe constructs the walker accepts. Anything outside the supported subset triggers a position-precise warning telling you to pre-compute the value in a `@:state` field instead.

## The three tiers

| Tier | Status | What's in it |
|---|---|---|
| **T1 — essentials** | Fully supported | Literals, state refs, subscripts, concat, ternaries, comparisons, locals from `ForEach` lambdas |
| **T2 — convenience** | Supported on a whitelist | `Std.string(x)` (auto-inserted by Haxe single-quote interpolation), property getters (`state.value` after typing) |
| **T3 — out of scope** | Not supported, raises a warning | Regex, reflection, runtime type checks, exceptions, user-defined enum pattern matching, arbitrary function calls |

## T1 — fully supported

### Literals

```haxe
Text.bind("Hello")              // → Text("Hello")
Text.bind('Count: ${42}')       // → Text("Count: \(42)")
.opacity(0.15)                  // → .opacity(0.15)
.foregroundHex("#ff3b30ff")     // → .foregroundStyle(Color(suiHex: "#ff3b30ff") ?? Color.primary)
```

### State refs

```haxe
Text.bind(userName.value)       // bridge mode: → Text("\(appState.userName)")
                                // standalone:   → Text("\(userName)")
.foregroundHex(tintHex.value)   // typed State<String> arg, no string literal
```

`qualifyStateName` adds the `appState.` prefix when the app declares any `@:expose` static (bridge mode); for standalone `@State` apps and component-local fields it stays bare.

### Array subscripts

Inside a `ForEach.byIndex(arr, i -> body)` lambda, both the iterated array and any parallel array can be subscripted by the typed `Int` index:

```haxe
ForEach.byIndex(todos, i ->
    new HStack([
        Text.bind(todos.value[i].title),
        Image.systemImage("circle.fill")
            .foregroundHex(calendarColors.value[i]),
    ])
)
```

The walker recognises `state.value[localFromLambda]` as a parallel-array access and emits `appState.<name>[i]`.

### String composition

Haxe single-quote interpolation desugars to `TBinop(OpAdd, …)` chains that the walker flattens into a single Swift literal:

```haxe
Text.bind('Page ${currentPage.value} / ${totalPages.value}')
// → Text("Page \(appState.currentPage) / \(appState.totalPages)")

Text.bind('${editorStartHour.value}h${editorStartMinute.value}')
// → Text("\(appState.editorStartHour)h\(appState.editorStartMinute)")
```

Direct concatenation with `+` works the same way:

```haxe
Text.bind("Prefix: " + name.value)
```

### Ternaries

```haxe
Text.bind(isVisible.value ? "shown" : "hidden")
// → Text("\((appState.isVisible ? "shown" : "hidden"))")

.foregroundHex(weekIsToday.value[i] ? "#ffffff" : "")
// inside a ForEach.byIndex — walker handles the per-row ternary
```

The Haxe typer rewrites ternaries in argument position to `{ var _hx; if (cond) _hx = a; else _hx = b; }` — the walker reconstructs the `TIf` from that block and emits the Swift ternary inline.

### Comparisons & boolean logic

```haxe
Text.bind(count.value > 0 ? "positive" : "zero or less")
.opacity(isHidden.value && !isPinned.value ? 0.0 : 1.0)
```

Supported operators: `==`, `!=`, `<`, `<=`, `>`, `>=`, `&&`, `||`, `!`, `+`, `-`, `*`, `/`, `%`.

### Lambda parameters

Both `ForEach` shapes give the body a typed local:

```haxe
// Element iteration
new ForEach(colors, color ->
    new Text(color).tag(color)         // color is String
)

// Index iteration
ForEach.byIndex(todos, i ->
    Text.bind(todos.value[i])           // i is Int
)
```

The walker tracks the lambda's `paramId` and substitutes Swift's matching loop variable when the typed AST references it.

## T2 — convenience

These work, but they're either auto-inserted by Haxe or recognised against a small whitelist.

### `Std.string` wrap

Single-quote interpolation `'${x}'` desugars to `Std.string(x) + …`. The walker peels the wrap transparently:

```haxe
Text.bind('${count.value}')      // count is Int — Haxe inserts Std.string
// → Text("\(appState.count)")
```

You almost never write `Std.string(…)` yourself; if you do, it works.

### Property getters

`state.value` on a `State<T>` is a Haxe property with a getter. After typing it becomes a `TCall(get_value, [])`. The walker recognises this shape and emits `appState.<state-name>` directly.

## T3 — not supported

The walker raises a warning for any construct outside T1/T2. Typical culprits:

```haxe
Text.bind(name.value.toLowerCase())           // method call on String — not whitelisted
Text.bind(Reflect.field(obj, "x"))            // reflection
Text.bind(myEnum.match(Some(_)))              // pattern match
Text.bind(try riskyCall() catch (e:Dynamic) "") // exceptions
```

**Workaround:** pre-compute the value in a `@:state` field and read that instead.

```haxe
// In your App class:
@:state var nameLower:String = "";

override function body():View {
    // Update the derived state from a bridge call or onAppear:
    return new VStack([
        Text.bind(nameLower)
    ]);
}
```

For complex per-row computations inside `ForEach`, follow the same pattern with a parallel `State<Array<…>>`:

```haxe
@:state var monthDayNumberHex:Array<String>;  // pre-computed per cell

ForEach.byIndex(monthIndices, i ->
    Text.bind(monthDayNumbers.value[i])
        .foregroundHex(monthDayNumberHex.value[i])  // typed access, no logic in modifier
)
```

This is the same pattern calendar-mac uses everywhere.

## Where the walker runs

| API | Walker entry point |
|---|---|
| `Text.bind(expr)` | `stringExprToSwift` in `SwiftGenerator.hx` |
| `.foregroundHex(expr)` / `.backgroundHex(expr)` | `resolveHexExpr` |
| `.opacity(expr)`, `.offset(x, y)`, `.scaleEffect(expr)`, `.proportionalOffset(x, y)`, `.proportionalFrame(w, h)`, `.blur(expr)`, `.brightness(expr)`, `.contrast(expr)`, `.saturation(expr)`, `.grayscale(expr)`, `.rotationEffect(expr)` | `resolveModifierValue` |
| `ForEach.byIndex(arr, i -> body)` | `forEachByIndexToSwift` + `extractItemExpr` per-row |
| `new ForEach(arr, item -> body)` (closure form) | `forEachToSwift` + `extractItemExpr` per-row |
| Action closures (`() -> Void`) | registered via `Callbacks.reg` / `Callbacks.indexed`, dispatched by id — see [Bridge](bridge.md#dispatch-by-id) |
| `.sheet`, `.popover`, `.alert`, `.confirmationDialog`, `.searchable`, `.fullScreenCover`, `.inspector` | direct `qualifyStateName` |
| `.onChange(of:)` | direct `qualifyStateName` |

All emitters call the shared `qualifyStateName(name)` helper to decide whether to prefix `appState.`. In bridge mode (`needsRuntimeBridge`), state-field names get the prefix; component bindings (`@:swiftBinding`) and standalone `@State` stay bare.

## Diagnostics

The walker warns at the exact source position of the unsupported expression:

```
clients/calendar-mac/src/App.hx:512:23: Warning : [sui] Text.bind: unsupported call expression — pre-compute in a @:state field instead.
```

When you see this, the emitted Swift falls back to `"<unsupported>"`. Replace the expression with a state-field read.

## See also

- **[Text & Labels](views/text-and-labels.md)** — `Text.bind` introductory examples
- **[Lists & Iteration](views/lists-and-iteration.md)** — `ForEach.byIndex` vs closure form vs legacy `"i"` form
- **[State & Actions](state/state-and-actions.md)** — action closures
- **[Bridge](bridge.md)** — `@:expose` Haxe functions, bridged modifier args
