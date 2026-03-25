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

Iterates over a `@State` array to render a view for each element.

```haxe
new ForEach(todos, "i",
    new HStack([
        Text.withState("{todos[i].title}"),
        new Spacer(),
        new Button("Delete", null,
            StateAction.CustomSwift("todos.remove(at: i)"))
    ])
)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `array` | `State` reference | The `@State` array variable |
| `itemName` | `String` | Iteration index variable name in generated Swift |
| `itemView` | `View` | View rendered for each element |

Access element properties with `Text.withState("{array[itemName].property}")`.

### List + ForEach Pattern

```haxe
new List([
    new ForEach(items, "i",
        new Text("Item")  // rendered for each element
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
