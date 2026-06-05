import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

/**
    Demonstrates the C++ bridge: Swift UI calling Haxe business logic.
    The `greet` function runs in Haxe/C++, called from SwiftUI.
**/
class BridgeApp extends App {
    static function main() {}

    var result:State<String>;

    public function new() {
        super();
        appName = "BridgeDemo";
        bundleIdentifier = "com.sui.bridgedemo";
        result = new State<String>("Press a button!", "result");
    }

    /** Haxe business logic: generates a greeting. Runs in C++, called from Swift. **/
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
            new Text("Haxe ↔ Swift Bridge")
                .font(FontStyle.LargeTitle),
            Text.bind(result.value)
                .font(FontStyle.Title2)
                .padding(),
            new Button("Greet from Haxe", () -> result.value = greet("World")),
            new Button("Fibonacci(20)", () -> result.value = 'fib(20) = ${fibonacci(20)}'),
        ]);
    }
}
