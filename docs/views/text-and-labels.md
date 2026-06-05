# Text & Labels

## Text

Displays static text content.

```haxe
new Text("Hello from Haxe!")
    .font(FontStyle.LargeTitle)
    .foregroundColor(ColorValue.Blue)
    .bold()
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `text` | `String` | The text to display |

Common modifiers: `.font()`, `.foregroundColor()`, `.bold()`, `.italic()`, `.multilineTextAlignment()`, `.lineLimit()`, `.padding()`

## Text.bind

Displays dynamic text driven by a typed Haxe expression. The macro inspects the typed AST and emits the matching Swift string-interpolation directly — no template strings, no text rewriter, every reference is type-checked at compile time.

```haxe
Text.bind(count.value)                 // State<Int>  → Text("\(appState.count)")
Text.bind('Count: ${count.value}')     // mixed       → Text("Count: \(appState.count)")
Text.bind(todos.value[i].title)        // inside ForEach.byIndex  → Text("\(appState.todos[i].title)")
Text.bind('${rating} / 5')             // component @Binding param → Text("\(rating) / 5")
```

**Supported inside the expression**: literals (`Int`/`Float`/`Bool`/`String`), `state.value` reads, array subscripts, string concatenation (`+`), single-quote interpolation (`'foo ${bar}h'`), ternaries (`c ? a : b`), comparisons, and lambda parameters of the enclosing `ForEach`. The macro raises a position-precise warning for any other expression — pre-compute it in a `@:state` field and reference that.

### Text.withState *(legacy)*

The original stringly template form, kept for backwards compatibility. Prefer `Text.bind` for new code.

```haxe
Text.withState("Count: {count}")           // Same as Text.bind('Count: ${count.value}')
Text.withState("{todos[i].title}")         // Same as Text.bind(todos.value[i].title)
```

`withState` references inside the template are pattern-matched at emission time and depend on the `rewriteStateRefsToAppState` text pass to prefix `appState.` — a fragile path that fails silently on patterns it doesn't recognise. The typed `Text.bind` walker has no such failure mode.

## Label

Displays an SF Symbol icon alongside text.

```haxe
new Label("Settings", "gear")
new Label("Favorites", "star.fill")
new Label("Search", "magnifyingglass")
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `title` | `String` | Label text |
| `systemImage` | `String` | SF Symbols icon name |

Browse SF Symbols at [developer.apple.com/sf-symbols](https://developer.apple.com/sf-symbols/).

## Image

Displays images from the asset catalog or SF Symbols.

```haxe
// From asset catalog
new Image("myPhoto")

// SF Symbols (system icons)
Image.systemImage("star.fill")
    .foregroundColor(ColorValue.Yellow)

// Resizable image
new Image("banner").resizable()
    .frame(null, 200)
```

**Constructors:**

| Constructor | Parameters | Description |
|-------------|-----------|-------------|
| `new Image(name)` | `name: String` | Asset catalog image |
| `Image.systemImage(name)` | `systemName: String` | SF Symbol |

**Methods:**

| Method | Returns | Description |
|--------|---------|-------------|
| `.resizable()` | `Image` | Makes the image resizable |
