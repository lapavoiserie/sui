# Controls

## Button

Triggers an action when tapped.

```haxe
// With a fluent StateAction
new Button("Increment", null, count.inc(1))

// With a Haxe closure (bridged automatically, no annotation needed)
new Button("Say Hello", () -> myState.value = "Hello!")

// With both (fluent StateAction for Swift, closure for Haxe-side effects)
new Button("+", () -> count.value = count.value + 1, count.inc(1))
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Button text |
| `action` | `() -> Void` | Optional Haxe closure (bridged automatically) |
| `stateAction` | `StateAction` | Optional declarative state mutation |

### Button.withView

Use a custom view as the button label:

```haxe
Button.withView(
    new HStack([
        Image.systemImage("plus.circle"),
        new Text("Add Item")
    ]),
    null,
    items.appendAction(someValue)
)
```

## TextField

A text input field bound to a `@State` string.

```haxe
new TextField("Enter your name...", "username")
    .textFieldStyle(TextFieldStyleValue.RoundedBorder)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `placeholder` | `String` | Placeholder text |
| `textBinding` | `String` | Name of the `@State var` (String) to bind to |

**Styles:**

| Style | Description |
|-------|-------------|
| `TextFieldStyleValue.Automatic` | System default |
| `TextFieldStyleValue.RoundedBorder` | Rounded border style |
| `TextFieldStyleValue.Plain` | No decoration |

## SecureField

A password input field that hides user input. Same API as `TextField`.

```haxe
new SecureField("Password", "password")
    .textFieldStyle(TextFieldStyleValue.RoundedBorder)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `placeholder` | `String` | Placeholder text |
| `textBinding` | `String` | Name of the `@State var` (String) to bind to |

Supports the same `textFieldStyle` modifier as `TextField`.

## TextEditor

A multi-line text input field bound to a `@State` string.

```haxe
new TextEditor("composeBody")
    .frame(null, 200)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `textBinding` | `String` | Name of the `@State var` (String) to bind to |

## Toggle

A boolean switch bound to a `@State` bool.

```haxe
new Toggle("Dark Mode", "isDarkMode")
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Toggle label |
| `isOnBinding` | `String` | Name of the `@State var` (Bool) to bind to |

## Slider

A range input bound to a `@State` number.

```haxe
new Slider("volume", 0.0, 100.0)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `valueBinding` | `String` | Name of the `@State var` (Float/Double) to bind to |
| `rangeMin` | `Float` | Minimum value |
| `rangeMax` | `Float` | Maximum value |

## ShareLink

A button that triggers the system share sheet — macOS Share menu on Mac, `UIActivityViewController` on iOS / iPadOS / visionOS. Maps to SwiftUI's `ShareLink(item:)`.

```haxe
// Default UI — system share-arrow icon
new ShareLink("https://example.com")

// Custom label
new ShareLink("https://example.com", "Share this link")
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `item` | `String` | The thing being shared. SwiftUI auto-detects URLs vs plain text from the string. |
| `label` | `String` (optional) | Custom label text. Without it, the default share-arrow icon is shown. |

## Picker

A selection control bound to a `@State` variable.

```haxe
new Picker("Color", "selectedColor", [
    new Text("Red"),
    new Text("Green"),
    new Text("Blue")
])
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Picker label |
| `selectionBinding` | `String` | Name of the `@State var` to bind to |
| `content` | `Array<View>` | Options (typically Text views) |
