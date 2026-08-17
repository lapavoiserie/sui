# sui

> Build native Apple apps in Haxe. &mdash; [GitHub](https://github.com/lapavoiserie/sui) | [Documentation](https://lapavoiserie.github.io/sui/#/)

**sui** is a framework that lets you write SwiftUI applications entirely in Haxe. Your Haxe code compiles to C++ via hxcpp and produces genuine native apps for macOS, iOS, iPadOS, and visionOS.

Your `body()` runs on the device: it builds a view tree, and SwiftUI is built from it at runtime. A state write reaches the views that display it, and nothing else. See [Render paths](render-paths.md) for what that replaced, and why the transpiler that emitted SwiftUI ahead of time is kept but no longer used.

## Why sui?

- **Write Haxe** &mdash; Use the language you know: type inference, pattern matching, macros, and the full Haxe ecosystem.
- **Native SwiftUI** &mdash; Every view, modifier, and interaction maps directly to SwiftUI. No web views, no wrappers.
- **All Apple Platforms** &mdash; Target macOS, iOS, iPadOS, and visionOS from a single codebase.

## How It Works

```mermaid
flowchart LR
    A["Your Haxe Code"] --> B["sui macros"]
    B --> C["Swift/SwiftUI"]
    B --> D["C++ (hxcpp)"]
    C & D --> E["Xcode Build"]
    E --> F["macOS App"]
    E --> G["iOS App"]
    E --> H["visionOS App"]
```

## Quick Example

```haxe
import sui.App;
import sui.View;
import sui.ui.*;

class HelloApp extends App {
    static function main() {}

    public function new() {
        super();
        appName = "HelloHaxe";
        bundleIdentifier = "com.sui.helloworld";
    }

    override function body():View {
        return new VStack([
            new Text("Hello from Haxe!")
                .font(FontStyle.LargeTitle)
                .padding(),
            new Text("Running on macOS")
                .foregroundColor(ColorValue.Secondary),
            new Spacer(),
            new Text("Built with sui")
                .font(FontStyle.Caption)
                .foregroundColor(ColorValue.Gray)
        ]);
    }
}
```

## Get Started

- **[Getting Started](getting-started.md)** &mdash; Install, create a project, build, and run.
- **[Views](views/README.md)** &mdash; 40+ built-in views.
- **[Modifiers](modifiers.md)** &mdash; 58+ view modifiers reference.
- **[State](state/README.md)** &mdash; State management, bindings, and observables.
- **[Animations](animations.md)** &mdash; State-driven `.animation(curve, state)`, transitions, and curves.
- **[Bridge](bridge.md)** &mdash; Transparent Haxe/C++ bridge (automatic closures + explicit exports).
- **[Native Extensions](native-extensions.md)** &mdash; Custom Swift files and SPM packages.
- **[Examples](examples/README.md)** &mdash; 18 example apps.

## Native capabilities

Anything that is not a view — the battery, the camera, secure storage — lives in
[`kui`](https://lapavoiserie.github.io/kui/), keyed by operating system so the
same implementation serves a `sui` application and any other backend building
for macOS or iOS.

hxcpp compiles a capability's C and Objective-C++ into `libhaxe.a`, and **Xcode**
performs the link, so a capability that needs a framework or a Swift Package
says so in its `xcode` payload. `sui`'s CLI reads it and merges it into the
generated `project.yml` before xcodegen runs — which is why the payload has to
be read *after* the Haxe compilation that writes it, not before.
