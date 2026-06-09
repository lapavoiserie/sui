# Controls

## Button

Triggers an action when tapped.

```haxe
// With a closure action (bridged automatically, no annotation needed)
new Button("Increment", () -> count.value++)

new Button("Say Hello", () -> myState.value = "Hello!")

// A bare () -> Void function reference works too
new Button("Login", MyApp.startLogin)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Button text |
| `action` | `() -> Void` | Optional action closure (bridged automatically) |

### Button.withView

Use a custom view as the button label:

```haxe
Button.withView(
    new HStack([
        Image.systemImage("plus.circle"),
        new Text("Add Item")
    ]),
    () -> items.value = items.value.concat([someValue])
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

## Stepper

An increment/decrement control bound to an `Int` `@State`.

```haxe
new Stepper("Quantity", "quantity", 1, 10)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Row label (shown by `Form`/`List`) |
| `valueBinding` | `String` | Name of the `@State var` (Int) to bind to |
| `minValue` / `maxValue` | `Int` | Inclusive range |

The label is **static** — it does not reflect the bound value. To show the running value, pair the Stepper with a bound `Text`:

```haxe
new HStack(null, 12, [
  Text.bind('Every ${interval.value}'),
  new Stepper("", "interval", 1, 99),
])
```

## IsoDatePicker / IsoTimePicker

Native date and time wheels that bind to a **`State<String>`** instead of a `Date`, so the Haxe side keeps a plain ISO string. `IsoDatePicker` round-trips `YYYY-MM-DD`; `IsoTimePicker` round-trips `HH:mm`. Sui emits a `Binding<Date>` adapter (shared `suiIsoParse`/`suiIsoFormat` helpers) so SwiftUI shows a real picker while the state stays a string.

```haxe
new IsoDatePicker("Start", "editorStartDateIso")
new IsoTimePicker("Start time", "editorStartTime").labelsHidden()
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Row label — pass `""` and add `.labelsHidden()` when an HStack already shows the field name |
| `isoStateName` | `String` | Name of the `State<String>` to bind to (`YYYY-MM-DD` for date, `HH:mm` for time) |

> **UTC-pinned by design.** The formatters are anchored to **UTC**, not the device's local time zone. This is deliberate: the picker displays exactly the wall-clock value held in the string, with no implicit local-offset shift. Store wall-clock values in the string and convert to/from real UTC instants yourself at the API boundary — otherwise an event authored at 09:00 can render an hour off across a DST edge.

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

## Menu

A drop-down menu containing buttons or nested `Menu`s. Maps to SwiftUI's `Menu`. The typical use case is a toolbar dropdown — clicking the label opens a popover with the actions. On macOS it adopts the system `NSMenu` look; on iOS it's a popover sheet.

```haxe
new Menu("Actions", [
    new Button("New", newAction),
    new Button("Open…", openAction),
    new Menu("Recent", [
        new Button("File 1", openFile1Action),
        new Button("File 2", openFile2Action),
    ]),
    new Button("Delete", deleteAction),
])
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | The text shown on the menu trigger |
| `content` | `Array<View>` | The menu items — typically `Button`s or nested `Menu`s |

Menus can be nested arbitrarily for sub-menus.

## CommandMenu (macOS menu bar)

A top-level menu in the macOS menu bar — appears next to **File / Edit / View / Help**. Maps to SwiftUI's `CommandMenu`. iOS, iPadOS and tvOS don't show a menu bar, so `CommandMenu`s are dropped at runtime on those platforms.

CommandMenus are declared by overriding `commands()` on your `App` subclass — *not* by including them in `body()`. The macro reads the `commands()` method at compile time and emits a `.commands { … }` modifier on the App's WindowGroup.

```haxe
class MyApp extends sui.App {
    public function new() {
        super();
        appName = "MyApp";
        bundleIdentifier = "com.example.myapp";
    }

    override function body():View {
        return new Text("Hello");
    }

    override function commands():Array<CommandMenu> {
        return [
            new CommandMenu("Calendar", [
                new Button("New Event", newEventAction)
                    .keyboardShortcut("n", ["command"]),
                new Button("Today", showTodayAction)
                    .keyboardShortcut("t", ["command"]),
            ]),
            new CommandMenu("View", [
                new Button("Month", showMonthAction)
                    .keyboardShortcut("1", ["command"]),
                new Button("Week", showWeekAction)
                    .keyboardShortcut("2", ["command"]),
                new Button("Day", showDayAction)
                    .keyboardShortcut("3", ["command"]),
            ]),
        ];
    }
}
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `label` | `String` | Menu title in the menu bar |
| `content` | `Array<View>` | Buttons (typically with `.keyboardShortcut`) — these become menu items |

Pair `CommandMenu`s with `.keyboardShortcut(...)` on each Button to expose the same shortcut both as a menu item and as a global ⌘ shortcut. See the [Keyboard modifier section](../modifiers.md#keyboard).

## Settings (Preferences window)

A separate macOS Preferences window — opened with **⌘,** or the system **App ▸ Preferences…** menu. Declared by overriding `settings()` on your `App` subclass. The returned view is rendered into its own SwiftUI `Settings` scene, alongside the main `WindowGroup`. If you don't override `settings()`, no Settings scene is emitted.

```haxe
class MyApp extends sui.App {
    @:state var darkMode:Bool = false;
    @:state var userName:String = "";

    override function body():View {
        return new VStack([
            new Text("Main window"),
            Text.bind('Dark mode: ${darkMode.value}'),
        ]);
    }

    override function settings():View {
        return new Form([
            new Toggle("Dark Mode", "darkMode"),
            new TextField("Display name", "userName"),
        ]);
    }
}
```

The Settings view shares state with the main `body()` automatically — toggles in Preferences immediately update the main window and vice versa. The macro emits a `SettingsView` Swift struct alongside `ContentView`, both bound to the same `AppState.shared` singleton.

iOS, iPadOS and tvOS ignore the Settings scene at runtime (those platforms route preferences through the system Settings app or an in-app view), so the generated `Settings { … }` block is wrapped in `#if os(macOS)`.
