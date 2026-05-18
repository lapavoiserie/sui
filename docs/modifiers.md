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
| `.overlay(content)` | `content: View` | Overlays another view on top |
| `.aspectRatio(ratio, contentMode)` | `ratio: Float`, `contentMode: String` | Constrain proportions (`"fit"` or `"fill"`) |
| `.offset(x, y)` | `x: Dynamic`, `y: Dynamic` | Offset view position (Float or state name) |

**Alignment values:** `Center`, `Leading`, `Trailing`, `Top`, `Bottom`, `TopLeading`, `TopTrailing`, `BottomLeading`, `BottomTrailing`

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
| `.backgroundMaterial(style)` | `style: MaterialStyle` | Translucent frosted-glass background (`.regularMaterial`, etc.) — adapts to dark/light, picks up content behind. |
| `.opacity(value)` | `value: Float` | Opacity (0.0 to 1.0) |
| `.tint(color)` | `color: ColorValue` | Accent/tint color |

**MaterialStyle values:** `Regular`, `Thin`, `UltraThin`, `Thick`, `UltraThick`, `Bar`

The `.backgroundMaterial` modifier gives you the translucent frosted-glass treatment that macOS uses on sidebars, popovers and toolbars. Each style is a different thickness — `Thin` lets more of the underlying content through, `Thick` is more opaque. `Bar` is the toolbar-specific variant.

```haxe
new VStack([...])
    .backgroundMaterial(MaterialStyle.Regular)

new VStack([...])
    .backgroundMaterial(MaterialStyle.Bar)
```

**ColorValue values:** `Primary`, `Secondary`, `Accent`, `Red`, `Orange`, `Yellow`, `Green`, `Blue`, `Purple`, `Pink`, `White`, `Black`, `Gray`, `Clear`, `Custom(hex)`

```haxe
new Text("Custom color")
    .foregroundColor(ColorValue.Custom("#EA8220"))
```

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

## Style

| Modifier | Parameters | Description |
|----------|-----------|-------------|
| `.textFieldStyle(style)` | `style: TextFieldStyleValue` | `.Automatic`, `.RoundedBorder`, `.Plain` |
| `.listStyle(style)` | `style: String` | `"inset"`, `"grouped"`, `"plain"`, `"sidebar"` |

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
