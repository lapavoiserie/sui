# Async Fetch

Demonstrates a blocking bridge call with a loading placeholder, all from a plain action closure.

## Full Source

```haxe
import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

class FetchApp extends App {
    static function main() {}

    var result:State<String>;

    public function new() {
        super();
        appName = "AsyncFetch";
        bundleIdentifier = "com.sui.asyncfetch";
        result = new State<String>("Press a button to fetch data", "result");
    }

    /**
        Fetch a URL and return its content. Runs in Haxe/C++ via the bridge,
        on the detached thread the action closure already runs on.
    **/
    public static function fetchUrl(url:String):String {
        var http = new haxe.Http(url);
        var data = "";
        http.onData = function(d:String) {
            data = d;
        };
        http.onError = function(e:String) {
            data = "Error: " + e;
        };
        http.request(false);
        return data.length > 500 ? data.substr(0, 500) + "..." : data;
    }

    override function body():View {
        return new NavigationStack(new VStack(null, 16, [
            new Text("Async Haxe Bridge").font(FontStyle.LargeTitle),
            new ScrollView([
                Text.bind(result.value)
                    .font(FontStyle.Body)
                    .padding()
            ]),
            new HStack(null, 12, [
                new Button("Fetch example.com", () -> {
                    result.value = "Loading...";
                    result.value = fetchUrl("https://example.com");
                }),
            ]).padding()
        ]).navigationTitle("Async Fetch"));
    }
}
```

## Walkthrough

### Bridge Function with HTTP

```haxe
public static function fetchUrl(url:String):String {
    var http = new haxe.Http(url);
    // ...
    http.request(false);
    return data;
}
```

This is an ordinary Haxe function &mdash; no annotation needed to call it from a closure.
(Add `@:expose` only if you also want to call it by name from hand-written Swift.)

### The Action Closure

```haxe
new Button("Fetch example.com", () -> {
    result.value = "Loading...";
    result.value = fetchUrl("https://example.com");
})
```

The closure runs on a detached thread, so the blocking `http.request(false)` is fine.
The two assignments are both seen by SwiftUI: the placeholder appears immediately, then
the result replaces it when the network call finishes. No manual `Task` wrapping &mdash;
the bridge already runs the closure off the main thread.

> [!NOTE]
> The old `StateAction.BridgeCallLoading(...)` variant has been removed. Write the
> placeholder assignment and the call back-to-back in one closure, as above.

## Run It

```bash
cd examples/async-fetch
haxelib run sui run macos
```
