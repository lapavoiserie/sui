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

## See also

- [Adding a backend](https://lapavoiserie.github.io/mui/#/adding-a-backend) — the
  whole contract, and the two rules the six backends made necessary.
- [Backend support](https://lapavoiserie.github.io/mui/#/backend-support) — the
  generated table of what every backend answers for every type. It is generated
  by reading these very files.
