# Async Fetch

Demonstrates async bridge calls with a loading state using `BridgeCallLoading`.

## Full Source

```haxe
import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class FetchApp extends App {
    static function main() {}

    @:state var result:String = "Press a button to fetch data";

    public function new() {
        super();
        appName = "AsyncFetch";
        bundleIdentifier = "com.sui.asyncfetch";
    }

    @:expose
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
                new Button("Fetch example.com", null,
                    StateAction.BridgeCallLoading("result", "Loading...",
                        "fetchUrl", "https://example.com")),
            ]).padding()
        ]).navigationTitle("Async Fetch"));
    }
}
```

## Walkthrough

### Bridge Function with HTTP

```haxe
@:expose
public static function fetchUrl(url:String):String {
    var http = new haxe.Http(url);
    // ...
    http.request(false);
    return data;
}
```

The `@:expose` annotation is needed here because `BridgeCallLoading` calls the function by name from Swift as `HaxeBridgeC.fetchUrl()`.

**Without @:expose**, the same logic works via a closure:

```haxe
// No annotation needed
public static function fetchUrl(url:String):String {
    var http = new haxe.Http(url);
    var data = "";
    http.onData = (d) -> data = d;
    http.onError = (e) -> data = "Error: " + e;
    http.request(false);
    return data.length > 500 ? data.substr(0, 500) + "..." : data;
}

// Call via closure — handle loading state yourself
new Button("Fetch example.com", () -> {
    result.value = "Loading...";
    result.value = fetchUrl("https://example.com");
})
```

### BridgeCallLoading (requires @:expose)

```haxe
StateAction.BridgeCallLoading("result", "Loading...", "fetchUrl", "https://example.com")
```

This generates Swift code that:

1. Immediately sets `result = "Loading..."` (UI shows loading state)
2. Wraps the bridge call in a `Task { @MainActor in ... }` (async)
3. When the bridge call completes, sets `result` to the return value

**Without @:expose (closure equivalent):**

```haxe
new Button("Fetch example.com", () -> {
    result.value = "Loading...";
    var http = new haxe.Http("https://example.com");
    http.onData = (d) -> result.value = d.length > 500 ? d.substr(0, 500) + "..." : d;
    http.onError = (e) -> result.value = "Error: " + e;
    http.request(false);
})
```

The `@:expose` + `BridgeCallLoading` version is more concise and handles the async wrapping for you. The closure version gives you full control but requires managing the loading state manually.

**Parameters (BridgeCallLoading):**

| Parameter | Value | Description |
|-----------|-------|-------------|
| `stateName` | `"result"` | State variable to update |
| `loadingValue` | `"Loading..."` | Value shown while loading |
| `functionName` | `"fetchUrl"` | Bridge function to call |
| `arg` | `"https://example.com"` | Argument to pass |

### Generated Swift

```swift
// What BridgeCallLoading generates:
result = "Loading..."
Task { @MainActor in
    result = HaxeBridgeC.fetchUrl("https://example.com")
}
```

This gives you a responsive UI &mdash; the loading indicator appears instantly, and the result replaces it when the network call finishes.

## Run It

```bash
cd examples/async-fetch
haxelib run sui run macos
```
