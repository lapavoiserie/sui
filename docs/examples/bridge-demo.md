# Bridge Demo

Demonstrates calling Haxe business logic from action closures. The `greet` and
`fibonacci` functions run in Haxe/C++ and are called directly from the button
closures. `@:expose` is kept here so the same functions can also be called by name
from hand-written Swift (`HaxeBridgeC.greet()`).

## Full Source

```haxe
import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

class BridgeApp extends App {
    static function main() {}

    var result:State<String>;

    public function new() {
        super();
        appName = "BridgeDemo";
        bundleIdentifier = "com.sui.bridgedemo";
        result = new State<String>("Press a button!", "result");
    }

    /** Haxe business logic: generates a greeting. Runs in C++. **/
    @:expose
    public static function greet(name:String):String {
        return 'Hello, $name! (from Haxe/C++)';
    }

    /** Haxe business logic: computes fibonacci. **/
    @:expose
    public static function fibonacci(n:Int):Int {
        if (n <= 1) return n;
        return fibonacci(n - 1) + fibonacci(n - 2);
    }

    override function body():View {
        return new VStack(null, 20, [
            new Text("Haxe <-> Swift Bridge")
                .font(FontStyle.LargeTitle),
            Text.bind(result.value)
                .font(FontStyle.Title2)
                .padding(),
            new Button("Greet from Haxe", () -> result.value = greet("World")),
            new Button("Fibonacci(20)", () -> result.value = 'fib(20) = ${fibonacci(20)}'),
        ]);
    }
}
```

## Walkthrough

### Defining Bridge Functions

```haxe
@:expose
public static function greet(name:String):String {
    return 'Hello, $name! (from Haxe/C++)';
}
```

These are ordinary Haxe functions that run in C++. The action closures call them
directly &mdash; no special action variant required. `@:expose` is not needed just to call
them from a closure; it's kept here only so the same function is reachable by name from
any custom Swift code as `HaxeBridgeC.greet()`.

### Calling from an Action

Call the function inside the closure and assign its result to the state variable:

```haxe
new Button("Greet from Haxe", () -> result.value = greet("World"))
```

The closure runs on a detached thread, so even a blocking computation keeps the UI
responsive. SwiftUI re-renders the `Text.bind(result.value)` when the assignment lands.

### Multiple Bridge Functions

```haxe
@:expose
public static function fibonacci(n:Int):Int {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

new Button("Fibonacci(20)", () -> result.value = 'fib(20) = ${fibonacci(20)}')
```

Any number of functions can be called this way. Add `@:expose` to any of them you also
want to invoke by name from hand-written Swift.

## Run It

```bash
cd examples/bridge-demo
haxelib run sui run macos
```
