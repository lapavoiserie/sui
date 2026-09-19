# Being a `mui` backend

[`mui`](https://lapavoiserie.github.io/mui/) lets one source build for every
backend in this family. `sui` is the one that draws through SwiftUI.

## The conformance lives here

Under `sui/mui/` — one file per entry in
[`mui.Contract`](https://github.com/lapavoiserie/mui/blob/main/src/mui/Contract.hx).
A `typedef` where the signature already matches, a small subclass where it does
not:

```haxe
package sui.mui;

typedef View = sui.View;
```

`mui` holds **no branch for `sui`**, and none for any other backend. It states
the vocabulary as data, and one line in the build file resolves it:

```
-D mui_backend=sui
--macro mui.macros.Bind.all()
```

`Bind` defines `mui.ui.Button` as an alias of `sui.mui.Button`, then checks
every constructor against the contract — arity, optionality, argument types — and
names what does not match, at the top of the build rather than at first use.

It used to be the other way round: `mui` held 132 conditional branches and had to
know all six backends. Adding a seventh meant editing twenty-two files in a
repository that had nothing to learn from it.

## What else is ours

`sui/mui/init.hxml` is the build file `mui init` writes into a new project. It
lives here because what a build for this backend needs — which libraries, which
generator macro, which output — is ours to state, and `mui` had no way of keeping
six of them honest.

`ForEach` is the one façade here that is more than a line. `sui` has two
`ForEach` shapes and which to emit depends on the render path, so the whole
transform moved here from `mui` — where it used to sit beside five others that
had nothing to do with it.

## Surfaces: the WidgetKit widget

`@:surface(Glance)` becomes a **WidgetKit widget** on iOS. It is the
snapshot-detached corner again, and the gap is wider here than anywhere else:
an Android widget is drawn by the launcher from views *our* process built,
while a WidgetKit widget is a **separate binary** — an app extension, its own
process, its own sandbox — that cannot call into the application at all.

So the picture has to land somewhere both binaries can read. That is an **App
Group** container, the only thing iOS lets them share, and both targets carry
the entitlement for it. Everything before that is identical to the other
hosts: the declaration's thunk runs, `sui.nui.Describe` turns the tree into
`nui` nodes, and `nui.Snapshot.project` turns those into pure data — the same
shape a Companion frame carries over the network and the same shape the
Android widget stores. One contract, three distances.

```
{"type":"VStack","props":{"spacing":8},"children":[
  {"type":"Text","props":{"text":"Count: 0"}},
  {"type":"Button","props":{"label":"+1"},"actions":{"onClick":0}}]}
```

A new picture is taken **whenever a cell the declaration reads is written**.
The declaration is evaluated inside its own effect (`GlancePublish.follow`), so
`rui` knows exactly which cells it depends on and a write to any of them
re-samples and republishes. The application asks for nothing.

It is also taken when the application leaves the foreground — the same moment
`aui` publishes on — which covers a change that came from somewhere no cell
saw.

**Not at construction.** The obvious place is wrong and fails loudly: a sui
`mui.App`'s constructor runs *before* the subclass has initialised its
`@:state` fields, so sampling there reads a null cell and takes the whole boot
down with it. The constructor only *remembers* the application
(`GlanceBridge.attach`); the scene-phase observer samples it later, when it is
whole.

### Three things that are not obvious

- **The publish symbol is resolved at runtime**, with `dlsym(RTLD_DEFAULT)`,
  not linked. `sui.mui.GlancePublish` is compiled into every sui application,
  widget or not — including the plain Haxe executable a macOS build links
  *before Xcode ever sees it*, a link with no Swift in it. A weak
  declaration does not save that: on Darwin `weak` marks a definition, and an
  undefined weak reference still has to resolve.
- **The extension's `Info.plist` must name every key itself.** An explicit
  `INFOPLIST_FILE` turns off the synthesis `GENERATE_INFOPLIST_FILE` performs,
  and an extension with no `CFBundleIdentifier` is reported as "Embedded
  binary's bundle identifier is not prefixed with the parent app's" — which
  points at the prefix rather than at the absence.
- **The entitlements file lives outside the `Widget` directory.** That
  directory is a source group, so anything inside it becomes a resource of the
  extension, and an entitlements file the build copies is an entitlements file
  "modified during the build".

And one thing that is *not* a trap, recorded because it cost hours anyway:
**the widget gallery populates when you tap its search field.** An empty
gallery is not evidence of anything. Nor is the line `Filtering out extension
… no descriptors` in `chronod`'s log: it is the ordinary purge that precedes
`Updating descriptor cache`, and it appears in builds that work perfectly. If
you need to know whether the system has your widget, the question to ask is
whether `Updating descriptor cache` appears, and the place to ask it is
`xcrun simctl spawn <UDID> log show --predicate 'subsystem == "com.apple.chrono"'`.

### Tapping the widget

A tap in a WidgetKit widget is an `AppIntent`, and the intent runs in the
*extension's* process — where the application's closures are not. That is a
different problem from Android's, where the tap already lands in our own
process, and it has only one honest answer: if the closure cannot come to the
tap, the application has to.

So the extension links the same hxcpp runtime the application does, boots it
headless when an intent fires, and constructs its own instance of the
application class. It samples the `Glance` declaration — which rebuilds an
`ActionTable` in *this* process — invokes the id the tap carried, then samples
again and republishes the new picture. Ids are keyed by **place**, so the
button the user pressed has the same id in both binaries; that is the same
property the first interactive Companion paid for, collected here across a
process boundary rather than a network.

What makes the second instance agree with the application is
[durable state](https://lapavoiserie.github.io/mui/#/state/durable): a
`@:state(durable)` cell is read from and written to a file in the **App Group
container** — the same container the picture travels through — and because
the app and the extension are two processes over one file, `put` is a
compare-and-set wrapped in an exclusive `flock`. A writer whose expected
sequence has moved does not overwrite; it re-reads and adopts. The application
takes in whatever the extension wrote when it returns to the foreground
(`scenePhase == .active`), which is why a widget tap and a running app do not
end up telling two stories. Measured on the simulator — three taps with the app
in the background took the shared store 4 → 7, and the same still-running app
process then showed 8 after a fourth — which proves the mechanism and not the
memory budget: a simulator has no jetsam, and only a real device will say
whether a 2 MB extension survives being one.

**Everything the extension did not read from the store is at its initial
value.** The second instance is a draft that never existed — a closure that
reads three cells and writes one is wrong there, and nothing on screen says
so. That is the sharpest edge of this design, and it belongs in the
declaration's mind, not in a footnote.

Two mistakes the code made first, neither of them guessable from the shape of
a snapshot:

- **The id is in `actions`, not `props`.** `nui.Snapshot` puts displayed
  values in `props` and action ids in a sibling `actions` object —
  `{"props":{"label":"+1"},"actions":{"onClick":0}}`. Reading `props.onClick`
  finds nothing and every button looks inert.
- **`0` is a valid id.** Action ids start at zero, so a widget cannot test for
  a zero and conclude "no action". Absence of the key is the only thing that
  means no action; a `0` means the first button in the tree.

### What is not built yet

**iOS only.** A macOS widget is not more code, it is a signing identity:
macOS refuses to build a target carrying an entitlements file without a
provisioning profile, while the iOS simulator is content with ad-hoc signing.

## The describer — serving detached surfaces

A mui app on sui can serve surfaces that live OUTSIDE this process: a
Companion panel projected to another machine over cafos today, widget
snapshots when P4a lands. Installing the describer is what makes sui
*capable* of it; the networked corner itself stays off until a build asks for
it with `-D mui_cafos`, without which a `@:surface(Companion)` declaration
does not compile. Both start from the same step — turning sui views
into `nui.Node` — and `sui.nui.Describe` is that step, signed onto the shared
`mui.surface.Describe` register by `sui.mui.App`'s constructor.

Describers speak the **canonical** mui prop names (`text`,
`label`+`onClick`, `isOn`+`onToggle`, `text`+`placeholder`+`onText`,
`value`+`min`+`max`+`onValue`) — never sui's internal spellings
(`textBinding`, `isOnBinding`) — so a snapshot of a sui-served tree and of a
cui- or wui-served one look the same on the wire, and one sink renders both.

Describing **samples**, which on sui means resolving: `LiveProps` defers
every displayed value into a `liveBuild` thunk, and the describer runs it —
the same move `ViewSource.valueOf` makes — so the wire carries the current
value, and the projecting effect subscribes to the cells the tree displays.
A `ConditionalView`'s condition is evaluated live, a `ForEach` splices into
its siblings, a `ViewComponent` expands through `body()`. Two-way controls
write back through the state registry with `set()` — a remote edit must
reach this machine's own SwiftUI too, which is why it is not
`_applyFromSwift`'s echo-free apply.

Checked end to end by `tests/run_describe.sh`: canon, LiveProps sampling,
snapshot round-trip, and remote-shaped invocations landing in closures and
`@:state` cells.

## The vocabulary, and the markup it makes possible

`sui` declares what its controls are, on the controls:

```haxe
@:node("Toggle")
class Toggle extends View {
	@:prop public var label:String;
	@:cell("isOn", "onToggle", "Bool") public var isOnBinding:String;
}
```

`nui.macros.Declarations` reads that at compile time — shared by every backend,
so `sui` says only what is its own (`sui.nui.Vocabulary.DIALECT`).
`sui.nui.Describe` is **generated** from those declarations, and `mui`'s markup
is checked against them:

```
--macro sui.nui.Vocabulary.registerWithMui()
```

A misspelt attribute names itself and lists what is accepted; a tag nothing
declares is refused. `tests/run_markup.sh` checks both.

### Why `@:cell` and not `@:prop`

Because the field holds a **name**, not a value. `sui`'s state lives on the
Swift side and is reached through a registry, so `isOnBinding` is a `String`
whatever the cell carries — and a `String` cannot say `Bool`. The third word
does.

That is the same line every other form draws, and it is worth stating because it
looks like an exception and is not: **the type answers when the field holds the
value, and the declaration answers only when nothing typed does.** A name is not
a value.

### `sui` describes and does not build

SwiftUI draws, so nothing in Haxe ever makes a control out of a node. There are
no builders to generate, no cell to make from a received value, and the two
checks that are about *building* do not apply: a read-only property is fine, and
a constructor argument no property covers is nobody's problem until something
has to call the constructor — `sui.ui.Text`'s argument is `text` and its field
is `content`.

### What stays hand-written, and why

Describing dispatches by class now, walking up to the nearest declared ancestor.
`sui`'s types are mostly flat, so the branch order never cost anything here —
but nothing about a flat hierarchy today stops a subclass tomorrow, and the walk
has no order to get wrong.

Four branches are asked before the declarations, and each says why where it is:

- **`NativeComponent`** — the node is already a node, in the canon of the
  library that defined it. It is sent as it was given.
- **`Image`** — one class, two node types: a canonical `src` crosses as an
  `Image`, an SF Symbol as an `Icon`. `@:node` says one name for one class, on
  purpose, so this cannot be expressed and should not be.
- **`Picker`** — it *translates*. The cell may hold an index or the chosen row's
  text, and moving between the two means reading the content of child views.
- **`ProgressView`** — what crosses is `cell / total`. A division is not a read.

The line is the same in all four: a declaration says **where the value is**, not
what to do with it. A translation, a calculation, a choice of type — that is
code, and it stays readable where it applies.

### One thing reading the declarations found

Scanning `sui.ui` compiles every module in it, and `LazyHStack` and `LazyVStack`
both failed: each was missing the import for the alignment enum in its sibling's
module. They had been broken since they were written. Nothing forced them, so
nobody saw it.

## Colour

`sui` resolves colours in SwiftUI, which is right: `Color.accentColor` is the
one the person set, and the semantic colours follow light, dark and increased
contrast without anybody asking.

What was missing is that **none of it reached the wire**. `sui.nui.Describe`
emitted no colour modifier at all, so a panel projected from this machine
arrived with nothing on it.

A colour now crosses as a `nui.Color`, and a role stays a role — the far side
resolves it with its own semantics rather than a number chosen here. Coming the
other way, `sui.nui.Colors.swift` turns one into a SwiftUI expression, and a
role becomes a **semantic** colour rather than a number:

| role | Swift |
|---|---|
| `accent` | `Color.accentColor` |
| `danger` | `Color.red` |
| `warning` | `Color.orange` |
| `success` | `Color.green` |
| `text` | `Color.primary` |
| `muted` | `Color.secondary` |

`.red` on Apple's platforms is not a fixed `#FF0000`: it shifts with the
display and with the person's accessibility settings. That is precisely what a
role crossing as a role buys.

A named `ColorValue` leaves as components — `Gray` becomes `#808080`. A name
resolves to nothing per-platform, so it cannot cross as one; `Primary`,
`Secondary` and `Accent` are the three that *are* about a purpose, and they
cross as roles. `Clear` adds no modifier: one asking for nothing is not a
modifier.

## See also

- [Adding a backend](https://lapavoiserie.github.io/mui/#/adding-a-backend) — the
  whole contract, and the two rules the six backends made necessary.
- [Backend support](https://lapavoiserie.github.io/mui/#/backend-support) — the
  generated table of what every backend answers for every type. It is generated
  by reading these very files.
