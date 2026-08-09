# Render paths

`sui` has had two ways to put a view on screen. Since this change there is one
by default, and the other is kept only so a build that depended on it still has
somewhere to go.

## The dynamic renderer — the path

The app runs. `body()` builds a Haxe view tree, and `DynamicView.swift` walks it
through [`nui`'s pull contract](https://lapavoiserie.github.io/nui/#/pull-mode),
building SwiftUI from it.

Nothing about your app is decided at compile time, which is what buys the three
things that matter:

- **Expressions run.** There is nothing to translate, so nothing that can be
  missed. What a transpiler would never reach costs nothing here.
- **Composition units expand.** A `ViewComponent` becomes its `body()`, a
  `ForEach` becomes siblings, a `ConditionalView` becomes the branch it selects.
  The renderer never learns what an `if` is.
- **A write reaches one view.** Values are deferred into thunks, so what is left
  reading during `body()` is what decides the tree's *shape* — and a write to
  anything else invalidates only the views that display it. See
  [Fine-grained updates](dynamic-renderer.md#fine-grained-updates).
- **It hosts a UI that isn't known at compile time.** A hot-reload loop, or a
  renderer driven by a live protocol.

The costs, stated rather than discovered:

- The renderer has a **vocabulary** — the switch in `DynamicView.swift` — and a
  type outside it is refused at compile time, naming it. That refusal is
  deliberate; drawing `?Badge` on a screen was the alternative.
- A leaf's deferred value is evaluated **twice** per view evaluation: once to
  report which cells it reads, once for the value itself. Memoising the
  dependency set would halve that and would be wrong — a thunk with a branch in
  it reads different cells from one value to the next.

## The static transpiler — decommissioned

`SwiftGenerator` read `body()` from the typed AST at compile time and emitted
SwiftUI ahead of time. Nothing of the view survived to runtime: no tree, no
walk, no bridge crossing per node.

It is still here, behind `-D sui_static` (or `sui build macos --static`), and
building with it says what it is:

```
Warning : [SUI] the static SwiftUI path is decommissioned and unmaintained.
  It translates a subset of Haxe, and a view type it cannot translate
  reaches Swift as a name that does not compile.
  Drop -D sui_static to use the dynamic renderer.
```

### Why it was set aside

Not because emitting SwiftUI ahead of time is a bad idea. Until recently it was
the **only** way sui could be reactive at all: SwiftUI records no dependency on
a state read that happens through a C bridge, so a dynamic build drew its first
frame and then froze — a tap ran the Haxe closure, the state moved, and the
screen stayed where it was.

That argument is spent. The renderer observes the app's own state writes now and
rebuilds from them, so what is left is a transpiler that has to translate
arbitrary Haxe to stay correct, against a renderer that simply runs it:

| | Dynamic | Static |
|---|---|---|
| A view expression it cannot handle | there is no such thing — it runs | emitted as a name Swift cannot resolve |
| `ViewComponent` | expanded by the source | a generated struct, reading `appState` |
| A view type it cannot draw | refused at compile time, naming it | `cannot find 'Badge' in scope`, in a generated file |
| A value write | reaches the view that displays it | updates one `@Binding` |
| A structural write | rebuilds the tree | re-runs the generated `body` |

The last two rows used to be the transpiler's, and were the reason to keep it
around: a write rebuilt the whole tree where generated SwiftUI updated one
binding. That is settled — values are deferred into thunks, the cells each node
displays are reported to SwiftUI, and one observable per cell means a write
invalidates the views that read it and no others.

So why keep the transpiler at all? Because *set aside* is a smaller claim than
*deleted*. It still emits SwiftUI an Apple engineer could read, it still needs
no bridge crossing per node, and nothing has been measured on a large tree
against a build that has been shipping. Removing it is a decision about sui's
future; this change is not that decision.

### `-D sui_hot_reload`

Still accepted, and now a no-op: it names what the default already does. So is
`sui build --watch`. Passing `-D sui_hot_reload` together with `-D sui_static`
is refused — one of the two is left over, and guessing which builds something
nobody asked for.

## Where the choice is made

In one place: `sui.macros.RenderPath`. Everything that branches on the answer
asks it there, so the deprecation warning belongs to the build rather than to
whichever branch happened to run first.

Output records which path it was built for, so switching back and forth
recompiles rather than reusing the other mode's Swift.
