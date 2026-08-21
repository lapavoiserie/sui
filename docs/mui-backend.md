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
