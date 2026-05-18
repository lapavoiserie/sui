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

## Menu

A drop-down menu containing buttons or nested `Menu`s. Maps to SwiftUI's `Menu`. The typical use case is a toolbar dropdown — clicking the label opens a popover with the actions. On macOS it adopts the system `NSMenu` look; on iOS it's a popover sheet.

```haxe
new Menu("Actions", [
    new Button("New", null, newAction),
    new Button("Open…", null, openAction),
    new Menu("Recent", [
        new Button("File 1", null, openFile1Action),
        new Button("File 2", null, openFile2Action),
    ]),
    new Button("Delete", null, deleteAction),
])
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | The text shown on the menu trigger |
| `content` | `Array<View>` | The menu items — typically `Button`s or nested `Menu`s |

Menus can be nested arbitrarily for sub-menus.
