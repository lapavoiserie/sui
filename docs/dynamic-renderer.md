# Dynamic Renderer

sui normally **compiles** your view tree to Swift ahead of time: the macro reads
`body()` at build time and emits static SwiftUI. The **dynamic renderer** flips
that around &mdash; it walks the Haxe view tree at **runtime** and rebuilds
SwiftUI from it, with no per-view codegen.

That makes sui usable as a **host for a UI that isn't known at compile time**: a
hot-reload loop, or a renderer driven by a live protocol (this is how rsx2ui's
native A2UI renderer is built &mdash; a WebSocket feeds surfaces that become a
sui view tree at runtime).

It also runs an ordinary sui app, which it did not use to. Three things had to
be true for that, and each is worth knowing:

- **It draws every view sui produces.** The renderer's vocabulary was the
  protocol's &mdash; it knew `Board` and `Canvas`, and 12 of sui's 51 view
  types. A `List` or a `Picker` drew a placeholder. All of them are covered now,
  and a type outside the vocabulary is [refused at compile
  time](#what-is-refused) rather than drawn as `?Type`.
- **A state write reaches the screen.** `State.set()` rebuilds the tree, with no
  poll delegate to register. See [Reacting to state](#reacting-to-state).
- **Bindings resolve.** A sui control names its cell &mdash; `new
  TextField("Name", "userName")` &mdash; because the transpiler turned that into
  `$appState.userName`. There is no `appState` here, so the name is resolved
  against the registry every `State` joins when it is constructed.

Enable it with `--watch`:

```bash
sui build macos --watch
```

Output records which path it was built for, so switching back and forth
recompiles rather than reusing the other mode's Swift.

## Nodes with no rendering of their own

A `ViewComponent`, a `ForEach` and a `ConditionalView` are read *at compile
time* by the transpiler: a component becomes a Swift struct, a loop becomes
`ForEach(0..<n)`, a condition becomes an `if`. A walker cannot read them that
way, so `sui.nui.ViewSource` expands them before the renderer sees them &mdash;
a component into its `body()`, a loop into siblings, a condition into the branch
it selects. The renderer needs no branch for an `if`, and none for a component.

Two shapes exist only for the transpiler and cannot be resolved at runtime:

| Shape | What happens |
|---|---|
| `new ForEach(items, "i", Text.withState("{items[i].title}"))` | The body is a string template with nothing to resolve it against. No items are built, rather than putting `{items[i].title}` on screen. |
| `new ConditionalView("name", …)` where `name` is in no registry | Neither branch is taken. `false` would be a guess about half the screen. |

Prefer the closure form, `new ForEach(items, item -> …)`, and pass the cell
itself rather than its name where you can.

## Reacting to state

`sui.state.State.set()` notifies the C bridge on every application write. On the
static path that updated the generated `AppState`, an `ObservableObject` SwiftUI
was already watching. A dynamic build generates no views, so there is no
published field to write &mdash; the renderer observes those writes itself,
rebuilds the tree, and posts to the host. Rebuilds are coalesced to one per turn
of the run loop, so a handler writing three states asks for one new tree.

The poll delegate below is still there, and is still what an app streaming its
UI from elsewhere needs. An app with a fixed `body()` no longer needs one.

## What is refused

Under `--watch`, a view type the renderer has no branch for stops the build,
naming it and listing what is covered:

```
src/MyApp.hx:32: The dynamic renderer cannot draw "Badge".
  Covered types: AdaptiveStack, AngularGradient, Board, Button, …
  Add a case to the switch in sui/runtime/DynamicView.swift.
```

The covered set is read from `DynamicView.swift` itself, so it cannot drift from
what the renderer actually draws.

## How it works

Instead of generating Swift per view, sui compiles a fixed **`DynamicView.swift`**
that walks the tree recursively through a C bridge into the running hxcpp
runtime. Your `body()` runs at runtime, produces a `View` tree, and each node is
read on demand.

```mermaid
flowchart TD
    A["SwiftUI: HotReloadRootView"] --> B["viewnode_get_root()"]
    B --> C["ViewNodeBridge (Haxe): _root = app.body()"]
    A --> D["DynamicView(node): switch on viewType"]
    D --> E["viewnode_get_type / _child / _text / _property …"]
    E --> C
    D --> F["recurse into children"]
    F --> D
```

Three layers:

- **`DynamicView.swift`** (framework) &mdash; the recursive renderer. A `ViewNode`
  wraps an opaque pointer to a Haxe `View`; `DynamicView` switches on its
  `viewType` and maps it to the SwiftUI equivalent, recursing into children and
  applying the modifier chain.
- **`ViewNodeBridgeC.cpp` / `.h`** (framework) &mdash; the C bridge. Each accessor
  registers the calling thread's stack with the hxcpp GC, calls the matching
  `sui.runtime.ViewNodeBridge` static through its **direct hxcpp symbol**, and
  returns a primitive or an opaque node pointer.
- **`sui.runtime.ViewNodeBridge`** (framework, Haxe) &mdash; holds the app and the
  current root, and exposes typed accessors over a `View` (`getViewType`,
  `getChildCount`, `getChild`, `getTextContent`, `getStringProperty`,
  `getModifierType`, …). It is `@:keep`: nothing in Haxe references it, so DCE
  would otherwise strip it.

## Bootstrap

The static bridge boots from `haxe_bridge_init`. The dynamic renderer instead
generates a small **`SuiBootC.cpp`** (the macro knows the concrete app class):

```cpp
extern "C" void viewnode_boot(void) {
    // hx::Boot() + __boot_all() once, then:
    auto app = ::YourApp_obj::__new();
    ::sui::runtime::ViewNodeBridge_obj::setApp(app);  // runs app.body()
}
```

`HotReloadRootView` calls `viewnode_boot()` exactly once (a lazily-initialised
Swift global) before the first traversal, so `viewnode_get_root()` always sees an
initialised runtime.

## The render loop

The tree is not static: something outside SwiftUI mutates it (a reload, an
incoming protocol message). The renderer polls on the **main thread** and
rebuilds only when something changed.

```mermaid
flowchart LR
    T["SwiftUI Timer (main)"] --> P["viewnode_poll()"]
    P --> D["ViewNodeBridge.poll(): delegate() → rebuild()?"]
    D -->|changed| R["reloadCount++ (withAnimation)"]
    R --> RE["DynamicView re-reads the tree"]
```

Register a poll delegate from your app; return `true` when the tree should
rebuild:

```haxe
ViewNodeBridge.setPoll(() -> myQueue.drainAndApply());  // Void -> Bool
```

`poll()` runs the delegate and calls `rebuild()` (re-invokes `app.body()`) when
it returns true. Bumps are wrapped in `withAnimation`, so with **stable node
identities** SwiftUI interpolates layout changes instead of snapping.

### Stable identity

By default a rebuild tears the tree down and rebuilds it &mdash; input focus is
lost, nothing animates. Tag each node with a `"nodeId"` property (any stable
string) and `DynamicView` uses it as the SwiftUI identity, so the framework diffs
across rebuilds: text fields keep focus, and moved elements animate.

```haxe
var v = new sui.ui.Text(label);
v.properties.set("nodeId", stableId);   // survive rebuilds
```

## Input and actions back

Two sinks let native controls and gestures report back into your Haxe app.

**Data sink** &mdash; a native input (TextField, Toggle, Slider…) writes a value
at a path:

```haxe
ViewNodeBridge.setDataSink((path, value) -> model.set(path, value));
```

sui's editable controls call `viewnode_set_data(path, value)` on change, which
routes here. Mark the node with `path`/`value` properties for the control to use.

**Action sink** &mdash; the renderer fires a named action with a JSON extra
context (e.g. a drag-and-drop drop):

```haxe
ViewNodeBridge.setActionSink((name, extraJson) -> dispatch(name, extraJson));
```

Buttons built at runtime dispatch differently: their closure sits on the live
tree (a GC root), so `viewnode_invoke_action(node)` calls it **directly** &mdash;
no id indirection, unlike the static bridge.

## Theming

A native host can take an app-provided accent (e.g. a surface's brand colour):

```haxe
ViewNodeBridge.setAccent("#7c3aed");   // hex; "" = platform default
```

`HotReloadRootView` reads it via `viewnode_theme_accent()` and applies `.tint`,
so native controls pick up the brand.

## C entrypoints

The bridge surface, all `extern "C"`:

| Function | Purpose |
|---|---|
| `viewnode_boot()` | Boot hxcpp + register the app (generated `SuiBootC.cpp`). |
| `viewnode_poll()` | Pump the poll delegate; returns 1 if the tree changed. |
| `viewnode_rebuild()` | Re-run `app.body()`. |
| `viewnode_get_root()` | Opaque pointer to the root node. |
| `viewnode_get_type` / `_child_count` / `_get_child` | Tree traversal. |
| `viewnode_get_text` / `_get_property` | Node content. |
| `viewnode_get_button_label` / `_invoke_action` | Buttons (direct dispatch). |
| `viewnode_modifier_count` / `_type` / `_float` / `_string` | Modifier chain. |
| `viewnode_set_data(path, value)` | Input edit → data sink. |
| `viewnode_fire_action(name, extraJson)` | Renderer action → action sink. |
| `viewnode_theme_accent()` | The accent to tint controls with. |

## What the build wires up

Under `--watch`, the CLI treats the app as a native-bridge build:

- compiles the hxcpp static library (`libhaxe.a`) plus `ViewNodeBridgeC.cpp` and
  the generated `SuiBootC.cpp`;
- copies `DynamicView.swift` and points `ContentView` at `HotReloadRootView`;
- emits an umbrella bridging header and the link flags.

It works without any action closures (the static bridge is suppressed in this
mode) &mdash; the ViewNode bridge and direct dispatch replace it.

> **See also:** the [Bridge](bridge.md) doc covers the *static* bridge used by
> normal (compiled) apps. The dynamic renderer is the runtime counterpart.
