# State Management

sui provides a reactive state system that maps to SwiftUI's state management.

## Overview

| Concept | Haxe | SwiftUI | Purpose |
|---------|------|---------|---------|
| `@:state` | `@:state var count:Int = 0` | `@State var count = 0` | View-local mutable state |
| `StateAction` | `count.inc(1)` | `count += 1` | Declarative state mutations (fluent API) |
| `Binding` | `Binding.fromState(state)` | `@Binding var value` | Two-way reference to parent state |
| `Observable` | `extends Observable` | `@Observable class` | Shared data models |
| `Text.bind` | `Text.bind(count.value)` | `Text("\(count)")` | Display state values |

## How It Works

1. Declare `@:state` fields in your App class
2. The framework generates matching `@State var` properties in Swift
3. Mutations happen through the fluent `StateAction` API (in Swift) or `state.value = x` (in Haxe via bridge)
4. SwiftUI automatically re-renders when state changes

## Quick Example

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
                .font(FontStyle.Title),
            new Button("+1", null, count.inc(1)),
            new Button("Reset", () -> count.value = 0)
        ]);
    }
}
```

The `@:state` metadata automatically creates a `State<Int>` field named `"count"`. You can read and write it with `count.value`, and the change flows to SwiftUI.

### Explicit State (alternative)

You can also use `State<T>` directly for more control:

```haxe
var count:State<Int>;

public function new() {
    super();
    count = new State<Int>(0, "count");
}
```

## Pages

- **[State & Actions](state/state-and-actions.md)** &mdash; `State<T>`, `StateAction`, `Text.bind`
- **[Binding](state/binding.md)** &mdash; `Binding`, `@:swiftBinding`, component binding
- **[Observable](state/observable.md)** &mdash; `Observable` classes and shared data models
