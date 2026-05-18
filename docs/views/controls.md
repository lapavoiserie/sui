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

**Styling:** chain `.buttonStyle(ButtonStyleValue.…)` to pick a SwiftUI style. Values: `Automatic`, `Plain`, `Borderless`, `Bordered`, `BorderedProminent`, `Link`.

```haxe
new Button("Save", null, saveAction)
    .buttonStyle(ButtonStyleValue.BorderedProminent)
```

**Keyboard shortcut:** chain `.keyboardShortcut(key, modifiers)` to expose the same action as a global ⌘-shortcut. See [Modifiers ▸ Keyboard](../modifiers.md#keyboard).

```haxe
new Button("New", null, newAction)
    .keyboardShortcut("n", ["command"])    // ⌘N
```

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

A selection control bound to a `@State` variable. Pair with `.pickerStyle(PickerStyleValue.Segmented)` to get the native macOS segmented switcher (translucent rounded fill on the active segment, adapts to dark/light mode automatically); add `.onChange("stateName", action)` to react to selection changes.

```haxe
new Picker("Color", "selectedColor", [
    new Text("Red").tag("red"),
    new Text("Green").tag("green"),
    new Text("Blue").tag("blue")
])

// Segmented switcher with a reaction:
new Picker("View", "viewMode", [
    new Text("Month").tag("month"),
    new Text("Week").tag("week"),
    new Text("Day").tag("day"),
])
    .pickerStyle(PickerStyleValue.Segmented)
    .onChange("viewMode", StateAction.CustomSwift(
        'Task.detached { _ = HaxeBridgeC.setViewMode(appState.viewMode) }'
    ))
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Picker label |
| `selectionBinding` | `String` | Name of the `@State var` to bind to |
| `content` | `Array<View>` | Options (typically Text views with `.tag(value)`) |

The `.tag(value)` modifier on each option binds it to a specific selection value. The Picker writes the tag of the user's pick into the bound state.

**Picker styles** (passed to `.pickerStyle(...)`): `Automatic`, `Inline`, `Menu`, `Palette`, `Segmented`, `Wheel` (iOS only).
