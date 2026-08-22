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

A new picture is taken when the application leaves the foreground — the same
moment `aui` publishes on — and whenever the application asks with
`mui.surface.Resample.request(Glance)`.

**Not at construction.** The obvious place is wrong and fails loudly: a sui
`mui.App`'s constructor runs *before* the subclass has initialised its
`@:state` fields, so sampling there reads a null cell and takes the whole boot
down with it. The constructor only *remembers* the application
(`GlanceBridge.attach`); the scene-phase observer samples it later, when it is
whole.

### Three things that are not obvious

- **The publish symbol is resolved at runtime**, with `dlsym(RTLD_DEFAULT)`,
  not linked. `sui.mui.GlancePublish` is compiled into every application that
  touches `mui.surface.Resample` — including the plain Haxe executable a macOS
  build links *before Xcode ever sees it*, a link with no Swift in it. A weak
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

### What is not built yet

**iOS only.** A macOS widget is not more code, it is a signing identity:
macOS refuses to build a target carrying an entitlements file without a
provisioning profile, while the iOS simulator is content with ad-hoc signing.

**Display only.** A tap in a WidgetKit widget is an `AppIntent`, and an intent
runs in a process where the application's closures are not — a different
problem from Android's, where the tap already lands in our own process. The
action ids are in the tree, waiting: `"actions":{"onClick":0}` above is one.

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

## See also

- [Adding a backend](https://lapavoiserie.github.io/mui/#/adding-a-backend) — the
  whole contract, and the two rules the six backends made necessary.
- [Backend support](https://lapavoiserie.github.io/mui/#/backend-support) — the
  generated table of what every backend answers for every type. It is generated
  by reading these very files.
