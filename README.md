# sui

Build **native Apple apps in Haxe**. Your code compiles to C++ through hxcpp and
Xcode produces a genuine SwiftUI application for macOS, iOS, iPadOS and
visionOS.

```haxe
import sui.App;
import sui.View;
import sui.ui.*;

class CounterApp extends App {
    @:state var count:Int = 0;

    public function new() {
        super();
        appName = "Counter";
        bundleIdentifier = "com.sui.counter";
    }

    override function body():View {
        return new VStack([
            Text.bind('Count: ${count.value}').font(FontStyle.Title).padding(),
            new HStack(null, 20, [
                new Button("-", () -> count.value--),
                new Button("+", () -> count.value++)
            ])
        ]);
    }
}
```

That is `examples/counter`, unabridged.

## Your `body()` runs on the device

Not at build time. It builds a view tree, SwiftUI is built from that tree at
runtime, and a state write reaches the views that display it and nothing else.

An earlier design transpiled `body()` into SwiftUI ahead of time. That
transpiler is kept but no longer used, and
[Render paths](https://lapavoiserie.github.io/sui/#/render-paths) says what
replaced it and why — worth reading before touching the `--static` flag.

## Getting started

```bash
haxelib git sui https://github.com/lapavoiserie/sui
haxelib run sui init MyApp
cd MyApp && haxelib run sui run          # macos, or: run ios
```

Needs Haxe 4.3+, hxcpp, Xcode and [xcodegen](https://github.com/yonaskolb/XcodeGen).

## Native capabilities

Anything that is not a view — the battery, the camera, secure storage — lives in
[`kui`](https://lapavoiserie.github.io/kui/), keyed by operating system, so the
same implementation serves a `sui` application and any other backend building
for the same platform.

## Part of La Pavoiserie

`sui` is one backend of [`mui`](https://lapavoiserie.github.io/mui/), which gives
an application one view vocabulary across six of them —
[`aui`](https://github.com/lapavoiserie/aui) for Android,
[`wui`](https://github.com/lapavoiserie/wui) for Windows,
[`cui`](https://github.com/lapavoiserie/cui) for the terminal, and others. The
same `body()` runs on all of them.

## Documentation

<https://lapavoiserie.github.io/sui/>

## Licence

MIT.
