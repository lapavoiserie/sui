# Lists & Iteration

## List

Displays rows of content in a scrollable container, similar to `UITableView`.

```haxe
new List([
    new Text("Item 1"),
    new Text("Item 2"),
    new Text("Item 3")
])
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `content` | `Array<View>` | Row views |

Commonly combined with `ForEach` for dynamic content and `Section` for grouping.

## ForEach

Iterates over a `State<Array<T>>` to render a view for each element. Three call shapes — pick the one matching how the body reads the iteration variable.

### Closure form *(preferred for element iteration)*

```haxe
new ForEach(colorOptions, color ->
    new Text(color).tag(color)
)
```

The lambda receives the **element** (`color: String`). References to other parallel arrays still need an index — use `ForEach.byIndex` instead. Generates `ForEach(appState.colorOptions, id: \.self) { color in … }`.

### `ForEach.byIndex` *(preferred for index iteration)*

```haxe
ForEach.byIndex(todos, i ->
    new HStack([
        Text.bind(todos.value[i].title),
        new Spacer(),
        new Button("Delete", () -> todos.value = todos.value.filter(t -> t != todos.value[i]))
    ])
)
```

The lambda receives the **index** (`i: Int`). Subscripts into the iterated array (`todos.value[i].title`) and any parallel arrays (`colors.value[i]`) flow through the typed walker into `appState.todos[i]` / `appState.colors[i]` — no stringly templates anywhere. Generates `ForEach(0..<appState.todos.count, id: \.self) { i in … }`.

The `Delete` action is a closure that references the iteration index `i`. Inside a
`ForEach` row, the macro lifts the closure into an indexed builder and Swift dispatches
it with the live loop index (`HaxeBridgeC.invokeIndexedAction`). A row closure may only
reference iteration parameters, `@:state` fields, App members and statics — not locals
of the enclosing method — and at most 2 levels of `ForEach` can be nested. See
[The Bridge](../bridge.md#dispatch-by-id).

### Legacy three-arg form

```haxe
new ForEach(todos, "i",
    Text.withState("{todos[i].title}")
)
```

Kept for backwards compatibility. Pass the iteration variable name as a `String` and rely on stringly templates inside the body. Prefer `ForEach.byIndex` for new code — same Swift output, but every reference is type-checked.

| Form | Lambda param | Best for |
|---|---|---|
| `ForEach(arr, item -> …)` | element | tagging, displaying elements verbatim |
| `ForEach.byIndex(arr, i -> …)` | index | parallel-array subscripts, per-row bridges |
| `new ForEach(arr, "i", body)` | (stringly) | legacy |

### List + ForEach Pattern

```haxe
new List([
    ForEach.byIndex(items, i ->
        Text.bind(items.value[i])
    )
])
```

## Section

Groups content with an optional header. Used inside `List` or `Form`.

```haxe
new Form([
    new Section("Account", [
        new TextField("Username", "username"),
        new TextField("Email", "email")
    ]),
    new Section("Preferences", [
        new Toggle("Notifications", "notificationsEnabled"),
        new Toggle("Dark Mode", "darkMode")
    ])
])
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `header` | `String` | Optional section header text |
| `content` | `Array<View>` | Section child views |

## Form

A container for data entry, typically used with `Section`.

```haxe
new Form([
    new Section("Settings", [
        new Toggle("Wi-Fi", "wifiEnabled"),
        new Slider("volume", 0, 100)
    ])
])
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `content` | `Array<View>` | Form content (usually Sections) |

Forms automatically style their children with a grouped appearance appropriate for the platform.
