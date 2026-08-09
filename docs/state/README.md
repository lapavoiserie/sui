# State Management

sui provides a reactive state system that maps to SwiftUI's state management.

## Overview

| Concept | Haxe | SwiftUI | Purpose |
|---------|------|---------|---------|
| `@:state` | `@:state var count:Int = 0` | `@State var count = 0` | View-local mutable state |
| Action | `() -> count.value++` | `count += 1` | A `() -> Void` closure that mutates state |
| `Binding` | `Binding.fromState(state)` | `@Binding var value` | Two-way reference to parent state |
| `Observable` | `extends Observable` | `@Observable class` | Shared data models |
| `Text.bind` | `Text.bind(count.value)` | `Text("\(count)")` | Display state values |

## How It Works

1. Declare `@:state` fields in your App class
2. The framework generates matching `@State var` properties in Swift
3. Mutations happen in action closures via `state.value = x` (run in Haxe, dispatched through the bridge)
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
            new Button("+1", () -> count.value++),
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

## What backs it

`State<T>` extends [`rui.state.State`](https://lapavoiserie.github.io/rui/#/state), the
reactive core shared with the other La Pavoiserie backends (`aui`, `wui`, `cui`, `qui`).
A read inside a `rui` effect registers a dependency, and a write re-runs the effects that
read it — on top of the Swift notification you already had.

Two things are specific to sui and worth knowing:

- **The Swift push is unconditional.** The shared core skips a write whose value compares
  equal; sui pushes *every* application write across the bridge anyway — on the static path
  that reaches `AppState`, on the dynamic one the renderer, which rebuilds or invalidates
  from it. An `Array` can be
  mutated in place, so equality proves nothing, and arrays cross the bridge as an empty
  string whose only job is to bump Swift's version counter and trigger a re-read from
  shared memory. Skipping it would silently freeze the UI on
  `todos.set(sameArrayMutatedInPlace)`.
- **`applyExternal(value)`** is the path a value takes when it comes *from* SwiftUI — a
  `TextField`, `Toggle`, `Picker` or `Slider` binding. It reaches Haxe effects and
  `onValueChanged`, but is **not** pushed back to Swift, which already holds it. The C
  bridge's `_applyFromSwift` now routes through it.

`onValueChanged(callback)` stays yours: it fires whichever side wrote the value.

## Pages

- **[State & Actions](state/state-and-actions.md)** &mdash; `State<T>`, action closures, `Text.bind`
- **[Binding](state/binding.md)** &mdash; `Binding`, `@:swiftBinding`, component binding
- **[Observable](state/observable.md)** &mdash; `Observable` classes and shared data models
