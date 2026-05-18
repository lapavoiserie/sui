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

Iterates over a `@State` array to render a view for each element. Two call shapes — the **closure form** is the modern API, the legacy three-arg form is kept for backward compatibility.

### Closure form

```haxe
new ForEach(colors, color ->
    new Text(color).tag(color)
)
```

Generates:

```swift
ForEach(colors, id: \.self) { color in
    Text("\(color)")
        .tag(color)
}
```

The lambda parameter is a typed Haxe value (the array's element type), so references to it inside child views — `Text(color)`, `.tag(color)`, `.foregroundHex(color)`, `.blur(blurAmounts.value[i])` — are checked at compile time and the macro emits the matching Swift expression. **No stringly templates inside modifier args.**

Two AST shapes are recognised inside the lambda:

1. **Bare lambda parameter** — `Text(color)` where `color` is the closure param. Emits the iterated element.
2. **Indexed parallel-array access** — `Text.withState("{names[i]}").foregroundHex(rowColors.value[i])` where the closure iterates an `Array<Int>` of indices. The macro detects `<State<Array<T>>>.value[<lambdaParam>]` and emits `appState.rowColors[i]`. Useful when multiple parallel state arrays drive one row.

```haxe
@:state var monthIndices:Array<Int> = [for (i in 0...42) i];
@:state var monthDayNumbers:Array<String> = [];
@:state var monthDayColors:Array<String> = [];

new ForEach(monthIndices, i ->
    Text.withState("{monthDayNumbers[i]}")
        .foregroundHex(monthDayColors.value[i])
)
```

### Legacy 3-arg form

```haxe
new ForEach("todos", "i",
    new HStack([
        Text.withState("{todos[i].title}"),
        new Spacer(),
        new Button("Delete", null,
            StateAction.CustomSwift("todos.remove(at: i)"))
    ])
)
```

The iteration variable name is passed as a String, and modifier args use stringly templates (`"todos[i]"`). Still supported — useful when the body needs raw Swift fragments — but new code should prefer the closure form.

**Parameters (legacy form):**

| Parameter | Type | Description |
|-----------|------|-------------|
| `arrayName` | `String` | Name of the `@State` array variable |
| `itemName` | `String` | Iteration index variable name in generated Swift |
| `itemView` | `View` | View rendered for each element |

### List + ForEach Pattern

```haxe
new List([
    new ForEach(items, item ->
        new Text(item)
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
