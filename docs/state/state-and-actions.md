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

The variable name is used directly in fluent `StateAction` calls, `Text.bind` expressions, and binding references.

## StateAction

`StateAction` provides declarative state mutations that generate inline Swift code. Actions use a fluent API where you call methods directly on typed state references.

### Arithmetic

```haxe
count.inc(1)    // count += 1
count.dec(1)    // count -= 1
```

### Assignment

```haxe
name.setTo("Haxe")  // name = "Haxe"
isOn.tog()           // isOn.toggle()
```

### Array Operations

```haxe
items.appendAction(newItem)   // items.append(newItem)
```

### Custom Swift

For complex mutations, write Swift directly:

```haxe
StateAction.CustomSwift('if !text.isEmpty { items.append(Item(title: text)); text = "" }')
```

### Bridge Calls

Call `@:expose` functions from Swift:

```haxe
// Synchronous
StateAction.BridgeCall(result, "greet", "World")
// → result = HaxeBridgeC.greet("World")

// Async with loading state
StateAction.BridgeCallLoading(result, "Loading...", "fetchUrl", "https://example.com")
// → result = "Loading..."; Task { result = HaxeBridgeC.fetchUrl("https://example.com") }

// Animated — chain .animated() on any action
showDetail.tog().animated(AnimationCurve.Spring)
// → withAnimation(.spring) { showDetail.toggle() }

count.inc(1).animated(AnimationCurve.EaseInOut)
// → withAnimation(.easeInOut) { count += 1 }
```

**Animation curves:** Use the `AnimationCurve` enum: `AnimationCurve.Default`, `AnimationCurve.EaseIn`, `AnimationCurve.EaseOut`, `AnimationCurve.EaseInOut`, `AnimationCurve.Spring`, `AnimationCurve.Linear`, `AnimationCurve.Bouncy`

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
                new Button("-", () -> count.value = count.value - 1,
                    count.dec(1)),
                new Button("+", () -> count.value = count.value + 1,
                    count.inc(1))
            ])
        ]);
    }
}
```

The fluent `StateAction` (e.g. `count.dec(1)`) handles the Swift-side state mutation for immediate UI updates. The closure runs the same logic on the Haxe/C++ side. Both are optional &mdash; use whichever fits your use case.
