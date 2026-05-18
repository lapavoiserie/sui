# Layout Views

## VStack

Arranges children vertically.

```haxe
new VStack([
    new Text("First"),
    new Text("Second"),
    new Text("Third")
])
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `alignment` | `HorizontalAlignment` | `null` (Center) | `.Leading`, `.Center`, `.Trailing` |
| `spacing` | `Float` | `null` (system default) | Space between children |
| `content` | `Array<View>` | required | Child views |

With alignment and spacing:

```haxe
new VStack(HorizontalAlignment.Leading, 12, [
    new Text("Left-aligned"),
    new Text("With 12pt spacing")
])
```

## HStack

Arranges children horizontally.

```haxe
new HStack([
    new Text("Left"),
    new Spacer(),
    new Text("Right")
])
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `alignment` | `VerticalAlignment` | `null` (Center) | `.Top`, `.Center`, `.Bottom`, `.FirstTextBaseline`, `.LastTextBaseline` |
| `spacing` | `Float` | `null` | Space between children |
| `content` | `Array<View>` | required | Child views |

```haxe
new HStack(null, 20, [
    new Button("-", null, count.dec(1)),
    new Button("+", null, count.inc(1))
])
```

## ZStack

Overlays children on top of each other.

```haxe
new ZStack([
    new Text("Background").font(FontStyle.LargeTitle).opacity(0.1),
    new Text("Foreground")
])
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `alignment` | `Alignment` | `null` (Center) | Position within the stack |
| `content` | `Array<View>` | required | Child views (last on top) |

## Spacer

Expands to fill available space.

```haxe
new VStack([
    new Text("Top"),
    new Spacer(),          // pushes "Bottom" to the bottom
    new Text("Bottom")
])
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `minLength` | `Float` | `null` | Minimum size |

## Shape primitives

`Rectangle`, `Circle`, `Capsule`, `Ellipse` are zero-arg shape views that map to their SwiftUI equivalents. Like all SwiftUI shapes, they have no intrinsic size — give them one via `.frame(...)` (or rely on the parent layout to size them). Fill with `.foregroundColor(...)` / `.foregroundHex(...)`.

```haxe
new Rectangle()
    .frame(100, 50)
    .foregroundColor(ColorValue.Blue)

new Circle()
    .frame(20, 20)
    .foregroundColor(ColorValue.Red)

new Capsule()
    .frame(100, 24)
    .foregroundColor(ColorValue.Accent)

new Ellipse()
    .frame(100, 50)
    .foregroundColor(ColorValue.Purple)
```

Useful as drawing primitives, decoration, overlays, and for chip-style backgrounds where a plain `cornerRadius` isn't enough. For more complex curves use `Path` (not yet wrapped) via `CustomSwift`.

## Gradients

Three gradient views — `LinearGradient`, `RadialGradient`, `AngularGradient` — map to their SwiftUI equivalents. Like shapes, they have no intrinsic size; use `.frame(...)` or place them as a `.background(...)` overlay.

```haxe
new LinearGradient(
    [ColorValue.Blue, ColorValue.Purple],
    "top", "bottom"
)

new RadialGradient(
    [ColorValue.Yellow, ColorValue.Red],
    "center", 0, 100
)

new AngularGradient(
    [ColorValue.Red, ColorValue.Orange, ColorValue.Yellow,
     ColorValue.Green, ColorValue.Blue, ColorValue.Purple],
    "center"
)
```

Generates:

```swift
LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)
RadialGradient(colors: [.yellow, .red], center: .center, startRadius: 0, endRadius: 100)
AngularGradient(colors: [.red, .orange, .yellow, .green, .blue, .purple], center: .center)
```

**Unit-point strings** (start/end/center): `"top"`, `"bottom"`, `"leading"`, `"trailing"`, `"topLeading"`, `"topTrailing"`, `"bottomLeading"`, `"bottomTrailing"`, `"center"`.

## ScrollView

Wraps content in a scrollable container.

```haxe
new ScrollView([
    new VStack([
        new Text("Line 1"),
        new Text("Line 2"),
        // ... many lines
    ])
])
```

**Parameters:**

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `content` | `Array<View>` | required | Scrollable child views |

## ConditionalView

Conditionally renders views based on state. Maps to SwiftUI's `if/else` in a `@ViewBuilder`.

### Boolean condition

Show one view when a boolean state is true, another when false:

```haxe
new ConditionalView(isLoggedIn,
    buildMainView(),     // shown when true
    buildLoginView()     // shown when false
)
```

The false branch is optional:

```haxe
new ConditionalView(showBanner, new Text("Welcome!"))
```

### String equality

Match a string state against a specific value:

```haxe
new ConditionalView(currentScreen, "login",
    buildLoginView(),     // shown when currentScreen == "login"
    buildDefaultView()    // shown otherwise
)
```

**Parameters:**

| Parameter | Type | Description |
|-----------|------|-------------|
| `stateRef` | `State<T>` | State reference to check |
| `trueView` | `View` | View shown when condition is true (boolean) or matched (string) |
| `falseView` | `View` | *(optional)* View shown otherwise |
| `matchValue` | `String` | *(string mode only)* Value to compare against |

### Animated transitions

Add `.transition()` to child views for enter/exit animations, and chain `.animated()` with an `AnimationCurve` to animate the toggle:

```haxe
new Button("Toggle", null,
    showDetail.tog().animated(AnimationCurve.Spring))

new ConditionalView(showDetail,
    detailView.transition("slide"),
    placeholder.transition("opacity")
)
```

**Transition styles:** `"slide"`, `"opacity"`, `"scale"`, `"move"`, `"push"`
