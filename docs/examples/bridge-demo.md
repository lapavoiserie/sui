# Bridge Demo

Demonstrates the explicit `@:expose` annotation for exposing named Haxe functions to Swift. Note that most bridging (closures, `@:state` updates, lifecycle handlers) is automatic and needs no annotation &mdash; `@:expose` is only for named function exports.

## Full Source

```haxe
import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class BridgeApp extends App {
    static function main() {}

    @:state var result:String = "Press a button!";

    public function new() {
        super();
        appName = "BridgeDemo";
        bundleIdentifier = "com.sui.bridgedemo";
    }

    @:expose
    public static function greet(name:String):String {
        return 'Hello, $name! (from Haxe/C++)';
    }

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
            new Button("Greet from Haxe", null,
                StateAction.CustomSwift('result = HaxeBridgeC.greet("World")')),
            new Button("Fibonacci(20)", null,
                StateAction.CustomSwift('result = "fib(20) = \\(HaxeBridgeC.fibonacci(20))"')),
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

`@:expose` tells the framework to generate a named Swift-callable wrapper as `HaxeBridgeC.greet()`. This is needed here because we want to call the function by name from `StateAction.CustomSwift` and get a return value.

**Without @:expose**, the same logic works via a closure:

```haxe
// No annotation needed — closure is bridged automatically
public static function greet(name:String):String {
    return 'Hello, $name! (from Haxe/C++)';
}

new Button("Greet from Haxe", () -> {
    result.value = greet("World");
})
```

### Calling from SwiftUI

**With @:expose** &mdash; call by name in a Swift expression:

```haxe
new Button("Greet from Haxe", null,
    StateAction.CustomSwift('result = HaxeBridgeC.greet("World")'))
```

**Without @:expose** &mdash; use a closure instead:

```haxe
new Button("Greet from Haxe", () -> result.value = greet("World"))
```

Both produce the same result. The `@:expose` version is useful when you need the return value in a `CustomSwift` expression or want to compose calls in Swift code.

### Multiple Bridge Functions

```haxe
@:expose
public static function fibonacci(n:Int):Int {
    if (n <= 1) return n;
    return fibonacci(n - 1) + fibonacci(n - 2);
}

// With @:expose:
new Button("Fibonacci(20)", null,
    StateAction.CustomSwift('result = "fib(20) = \\(HaxeBridgeC.fibonacci(20))"'))

// Without @:expose:
new Button("Fibonacci(20)", () -> {
    result.value = "fib(20) = " + fibonacci(20);
})
```

Any number of `@:expose` functions can be defined. They all become available as `HaxeBridgeC.functionName()` in Swift.

## Run It

```bash
cd examples/bridge-demo
haxelib run sui run macos
```
