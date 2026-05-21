# Counter

A counter app demonstrating state management with `@:state`, the fluent `StateAction` API, and `Text.bind`.

## Full Source

```haxe
import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class CounterApp extends App {
    static function main() {}

    @:state var count:Int = 0;

    public function new() {
        super();
        appName = "Counter";
        bundleIdentifier = "com.sui.counter";
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

## Walkthrough

### Declaring State

```haxe
@:state var count:Int = 0;
```

`@:state` creates a reactive integer. The variable name is used in generated Swift (`@State var count: Int = 0`). No constructor initialization needed.

### Displaying State

```haxe
Text.bind('Count: ${count.value}')
```

`Text.bind` accepts any String-typed Haxe expression. sui walks the typed AST and emits `Text("Count: \(count)")` in Swift, so the text updates automatically when the state changes. Use single-quoted Haxe strings so `${...}` interpolation is in effect.

### Mutating State

```haxe
new Button("-", () -> count.value = count.value - 1,
    count.dec(1))
```

Each button has two actions:

1. **Haxe closure** `() -> count.value = count.value - 1` &mdash; Runs on the Haxe/C++ side, bridged automatically (no `@:expose` needed)
2. **Fluent StateAction** `count.dec(1)` &mdash; Generates Swift `count -= 1` for immediate UI update

Both are optional. Use the fluent `StateAction` API for instant SwiftUI updates, closures for Haxe-side logic.

### Layout

```haxe
new HStack(null, 20, [...])
```

`null` alignment (default center), `20` points spacing between the two buttons.

## Run It

```bash
cd examples/counter
haxelib run sui run macos
```
