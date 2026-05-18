# Modifiers

All views support modifier chaining. Each modifier returns the view, so you can chain them:

```haxe
new Text("Styled")
    .font(FontStyle.Title)
    .foregroundColor(ColorValue.Blue)
    .bold()
    .padding()
```

## Layout

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.padding()` | none | Default system padding |
| `.padding(value)` | `value: Float` | Fixed padding on all edges |
| `.frame(width, height, alignment)` | `width: Float`, `height: Float`, `alignment: Alignment` | All optional. Sets size constraints |
| `.fillWidth()` | none | Equivalent to `.frame(maxWidth: .infinity)` — stretches the view across its container's full width. |
| `.fillHeight()` | none | `.frame(maxHeight: .infinity)` |
| `.fillBoth()` | none | `.frame(maxWidth: .infinity, maxHeight: .infinity)` |
| `.fixedSize(horizontal, vertical)` | `horizontal: Bool` (default `false`), `vertical: Bool` (default `true`) | Prevent the view from being shrunk on the given axes. Useful when a `Text` or `List` collapses to zero inside a flexible parent. |
| `.overlay(content)` | `content: View` | Overlays another view on top |
| `.aspectRatio(ratio, contentMode)` | `ratio: Float`, `contentMode: String` | Constrain proportions (`"fit"` or `"fill"`) |
| `.offset(x, y)` | `x: Dynamic`, `y: Dynamic` | Offset view position (Float or state name) |

**Alignment values:** `Center`, `Leading`, `Trailing`, `Top`, `Bottom`, `TopLeading`, `TopTrailing`, `BottomLeading`, `BottomTrailing`

The `fill*` helpers exist because `.frame(maxWidth: .infinity)` is by far the most common workaround for SwiftUI containers — `List` inside a `.sheet`, cells inside a `LazyVGrid` — that collapse to their content's intrinsic width without an explicit stretch.

## Typography

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.font(style)` | `style: FontStyle` | Sets the font |
| `.bold()` | none | Bold weight |
| `.italic()` | none | Italic style |
| `.multilineTextAlignment(alignment)` | `alignment: TextAlignment` | `.Leading`, `.Center`, `.Trailing` |
| `.lineLimit(lines)` | `lines: Int` | Maximum number of lines |

**FontStyle values:**

| Style | Usage |
|-------|-------|
| `FontStyle.LargeTitle` | Main screen titles |
| `FontStyle.Title` | Section titles |
| `FontStyle.Title2` | Subsection titles |
| `FontStyle.Title3` | Minor titles |
| `FontStyle.Headline` | Emphasized body text |
| `FontStyle.Subheadline` | Secondary emphasis |
| `FontStyle.Body` | Main content |
| `FontStyle.Callout` | Callout text |
| `FontStyle.Footnote` | Footnotes |
| `FontStyle.Caption` | Caption text |
| `FontStyle.Caption2` | Smaller captions |
| `FontStyle.Custom(name, size)` | Custom font name and size |

## Color & Appearance

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.foregroundColor(color)` | `color: ColorValue` | Text/icon color |
| `.background(color)` | `color: ColorValue` | Background color |
| `.opacity(value)` | `value: Float` | Opacity (0.0 to 1.0) |
| `.tint(color)` | `color: ColorValue` | Accent/tint color |
| `.foregroundHex(expr)` | `expr: Dynamic` | Foreground colour from a runtime hex string. See below for the accepted shapes. |
| `.backgroundHex(expr)` | `expr: Dynamic` | Same as `foregroundHex` but for the background fill. |

**ColorValue values:** `Primary`, `Secondary`, `Accent`, `Red`, `Orange`, `Yellow`, `Green`, `Blue`, `Purple`, `Pink`, `White`, `Black`, `Gray`, `Clear`, `Custom(hex)`

```haxe
new Text("Custom color")
    .foregroundColor(ColorValue.Custom("#EA8220"))
```

### `foregroundHex` / `backgroundHex`

For colours that come from a `@State` value at runtime (per-row tinting in a `ForEach`, theme switches, server-supplied colours, …) the `ColorValue` enum is too rigid. The `*Hex` variants accept a runtime expression and parse it through `Color(suiHex:)`. Invalid or empty strings fall through to `Color.primary` / `Color.clear` via the nil-coalescing operator, so it's safe to pass `""` to mean "default".

Three shapes are recognised:

1. **String literal** — embedded verbatim into the generated Swift, then run through the body's appState-prefix pass. Useful for the legacy `"name"` / `"name[i]"` patterns.

   ```haxe
   new Text("●").foregroundHex("calendarColor");
   new Text("●").foregroundHex("calendarColors[i]");
   ```

2. **Typed `State<String>` field reference** — no `.value`, no string, no quoting:

   ```haxe
   @:state var tint:String = "#EA8220";

   new Text("•").foregroundHex(tint);   // → appState.tint
   ```

3. **Closure-form ForEach item ref** — inside a `new ForEach(arr, item -> …)` lambda, pass the iteration parameter (or a parallel-array subscript) directly:

   ```haxe
   new ForEach(colors, color ->
       new Text("•").foregroundHex(color)
   )

   new ForEach(indices, i ->
       new Text("•").foregroundHex(rowColors.value[i])
   )
   ```

   See [Views ▸ Lists & Iteration](views/lists-and-iteration.md#closure-form-foreach) for the full lambda pattern.

## Shape

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.cornerRadius(radius)` | `radius: Float` | Rounds corners |
| `.clipShape(shape)` | `shape: ShapeType` | Clips to a shape |

**ShapeType values:** `Rectangle`, `RoundedRectangle(cornerRadius)`, `Circle`, `Capsule`

## Visual Effects

Pass a `Float` for a static value, or a `State<Float>` reference for dynamic binding.

Each parameter accepts a `Float` (static) or a `State<Float>` (reactive). Type-checked at compile time.

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.blur(radius)` | `radius: StateOr<Float>` | Gaussian blur |
| `.scaleEffect(scale)` | `scale: StateOr<Float>` | Scale transform |
| `.rotationEffect(degrees)` | `degrees: StateOr<Float>` | Rotation in degrees |
| `.offset(x, y)` | `x, y: StateOr<Float>` | Offset position |
| `.brightness(amount)` | `amount: StateOr<Float>` | Adjust brightness (-1 to 1) |
| `.contrast(amount)` | `amount: StateOr<Float>` | Adjust contrast |
| `.saturation(amount)` | `amount: StateOr<Float>` | Adjust saturation |
| `.grayscale(amount)` | `amount: StateOr<Float>` | Grayscale (0 to 1) |

```haxe
@:state var blurAmount:Float = 0.0;

// Static value
new Image("photo").blur(5.0)

// State-bound — animates when blurAmount changes
new Image("photo").blur(blurAmount)
```

## Navigation

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.navigationTitle(title)` | `title: String` | Sets the navigation bar title |
| `.navigationDestination(content)` | `content: View` | Destination for navigation |
| `.toolbar(content)` | `content: View` | Adds toolbar items |
| `.toolbarItem(placement, content)` | `placement: String`, `content: View` | Toolbar item with placement |

**Placement values:** `topBarTrailing`, `topBarLeading`, `bottomBar`, `automatic`

## Interaction

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.disabled(isDisabled)` | `isDisabled: Bool` | Disables interaction (default: `true`) |
| `.searchable(textBinding, prompt)` | `textBinding: String`, `prompt: String` | Adds a search bar |
| `.badge(value)` | `value: Dynamic` | Badge on tab items or list rows |
| `.tag(value)` | `value: String` | Tag for Picker selection matching |
| `.onChange(stateName, action)` | `stateName: String`, `action: StateAction` | Runs a StateAction whenever the named state's value changes. Maps to SwiftUI's `.onChange(of:_:)`. |

The `onChange` modifier is the standard hook to react to a `Picker` selection, a `TextField` edit, or a `Toggle` flip without polling:

```haxe
new Picker("Mode", "viewMode", [...])
    .pickerStyle(PickerStyleValue.Segmented)
    .onChange("viewMode", StateAction.CustomSwift(
        'Task.detached { _ = HaxeBridgeC.setViewMode(appState.viewMode) }'
    ))
```

The generated Swift is `.onChange(of: appState.viewMode) { _, _ in <action> }` — the closure receives both the previous and new values, but the StateAction body can simply read the current `appState.viewMode` since the change has already been applied.

## Style

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.textFieldStyle(style)` | `style: TextFieldStyleValue` | `.Automatic`, `.RoundedBorder`, `.Plain` |
| `.listStyle(style)` | `style: String` | `"inset"`, `"grouped"`, `"plain"`, `"sidebar"` |
| `.buttonStyle(style)` | `style: ButtonStyleValue` | See values below |
| `.pickerStyle(style)` | `style: PickerStyleValue` | See values below |

**ButtonStyleValue:** `Automatic`, `Plain`, `Borderless`, `Bordered`, `BorderedProminent`, `Link`

```haxe
new Button("Save", null, saveAction)
    .buttonStyle(ButtonStyleValue.BorderedProminent)
```

**PickerStyleValue:** `Automatic`, `Inline`, `Menu`, `Palette`, `Segmented`, `Wheel` (iOS only)

The most useful value on macOS is `Segmented` — the native switcher control with a translucent rounded fill on the selected segment. Standard pattern for view-mode toolbars.

```haxe
new Picker("View", "viewMode", [
    new Text("Month").tag("month"),
    new Text("Week").tag("week"),
    new Text("Day").tag("day"),
])
    .pickerStyle(PickerStyleValue.Segmented)
    .onChange("viewMode", StateAction.CustomSwift(
        'Task.detached { _ = HaxeBridgeC.setViewMode(appState.viewMode); await MainActor.run {} }'
    ))
```

## Presentation

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.sheet(binding, content)` | `binding: State<Bool>`, `content: View` | Modal sheet |
| `.fullScreenCover(binding, content)` | `binding: State<Bool>`, `content: View` | Full-screen modal |
| `.popover(binding, content)` | `binding: State<Bool>`, `content: View` | Popover |
| `.alert(title, binding, message)` | `title: String`, `binding: State<Bool>`, `message: String` | Alert dialog |
| `.confirmationDialog(title, binding, content)` | `title: String`, `binding: State<Bool>`, `content: View` | Action sheet |
| `.contextMenu(content)` | `content: View` | Long-press context menu |

```haxe
new VStack([...])
    .sheet(showSheet, new Text("Sheet content"))
    .alert("Warning", showAlert, "Are you sure?")
    .contextMenu(new Button("Delete", null, StateAction.CustomSwift("deleteItem()")))
```

## Gestures

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.onTapGesture(action)` | `action: StateAction` | Runs a StateAction when tapped |
| `.onLongPressGesture(action)` | `action: StateAction` | Runs a StateAction on long press |

```haxe
new Text("Tap me")
    .onTapGesture(selected.setTo("true"))

new Text("Hold me")
    .onLongPressGesture(showMenu.tog())
```

## Lifecycle

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.onAppear(action)` | `action: () -> Void` | Closure when view appears |
| `.onDisappear(action)` | `action: () -> Void` | Closure when view disappears |
| `.task(action)` | `action: () -> Void` | Async closure on appear |
| `.onAppearAction(action)` | `action: StateAction` | StateAction on appear |
| `.taskAction(action)` | `action: StateAction` | StateAction async on appear |
| `.onSubmit(action)` | `action: () -> Void` | Closure on form/text submit |
| `.refreshable(action)` | `action: () -> Void` | Pull-to-refresh closure |
| `.swipeActions(content)` | `content: View` | Swipe actions on list rows |

```haxe
new List([...])
    .refreshable(() -> loadData())
    .listStyle("inset")

new VStack([...])
    .taskAction(StateAction.BridgeCallLoading(data, "Loading...", "fetchData", ""))
```

## Accessibility

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.accessibilityLabel(label)` | `label: String` | Screen reader label |

## Animation

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.animation(curve, ?value)` | `curve: AnimationCurve`, `value: StateOr<Float>` | Animate changes with an `AnimationCurve` enum value |
| `.transition(style)` | `style: String` | Enter/exit transition for conditional views |

**Animation curves:** `AnimationCurve.Default`, `AnimationCurve.EaseIn`, `AnimationCurve.EaseOut`, `AnimationCurve.EaseInOut`, `AnimationCurve.Spring`, `AnimationCurve.Linear`, `AnimationCurve.Bouncy`

**Transition styles:** `"slide"`, `"opacity"`, `"scale"`, `"move"`, `"push"`

```haxe
// Animate when a State<Float> reference changes
new Text("Hello")
    .scaleEffect(scale)
    .animation(AnimationCurve.Spring, scale)

// Transition on conditional views
new ConditionalView(showDetail,
    detailView.transition("slide"),
    placeholder.transition("opacity")
)
```

### Animated State Mutations

Chain `.animated()` on any fluent `StateAction` to animate the change. Use the `AnimationCurve` enum for the curve:

```haxe
// Without animation — instant
new Button("Toggle", null, expanded.tog())

// With animation — smooth spring
new Button("Toggle", null,
    expanded.tog().animated(AnimationCurve.Spring))
```

Works with any action:

```haxe
count.inc(1).animated(AnimationCurve.EaseInOut)
scale.setTo(1.5).animated(AnimationCurve.Spring)
StateAction.CustomSwift("offset = offset == 0 ? 50 : 0").animated(AnimationCurve.Bouncy)
```
