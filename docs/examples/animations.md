# Animations

Demonstrates the animation primitives: the `.animation(curve, state)` modifier with `AnimationCurve`, and `.transition()`. Actions are plain closures &mdash; the curves live on the views.

## Full Source

```haxe
class AnimApp extends App {
    static function main() {}

    @:state var showDetail:Bool = false;
    @:state var scale:Float = 1.0;
    @:state var rotation:Float = 0.0;
    @:state var offset:Float = 0.0;

    public function new() {
        super();
        appName = "Animations";
        bundleIdentifier = "com.sui.animations";
    }

    override function body():View {
        return new VStack(null, 30, [
            new Text("Animations")
                .font(FontStyle.LargeTitle),

            new GroupBox("Animated Card", [
                new Text("Hello!")
                    .font(FontStyle.Title)
                    .padding()
            ])
            .scaleEffect(scale)
            .rotationEffect(rotation)
            .offset(offset, 0)
            .animation(AnimationCurve.Spring, scale)
            .animation(AnimationCurve.Spring, rotation)
            .animation(AnimationCurve.EaseInOut, offset)
            .padding(),

            // Plain closures — they animate because of the .animation
            // modifiers declared on the card above.
            new HStack(null, 15, [
                new Button("Bounce", () -> scale.value = scale.value == 1.0 ? 1.3 : 1.0),
                new Button("Spin", () -> rotation.value += 90),
                new Button("Slide", () -> offset.value = offset.value == 0 ? 50 : 0),
                new Button("Reset", () -> {
                    scale.value = 1;
                    rotation.value = 0;
                    offset.value = 0;
                })
            ]),

            new Button("Toggle Detail", () -> showDetail.value = !showDetail.value),

            new ConditionalView(showDetail,
                new VStack([
                    new Text("Detail View").font(FontStyle.Headline),
                    new Text("This appeared with a slide transition")
                        .foregroundColor(ColorValue.Secondary)
                ])
                .padding()
                .background(ColorValue.Blue)
                .foregroundColor(ColorValue.White)
                .cornerRadius(12)
                .transition("slide"),

                new Text("Tap 'Toggle Detail' to show content")
                    .foregroundColor(ColorValue.Gray)
                    .transition("opacity")
            )
        ]).padding()
            .animation(AnimationCurve.Spring, showDetail);
    }
}
```

## Walkthrough

### State-Bound Visual Effects

```haxe
.scaleEffect(scale)
.rotationEffect(rotation)
.animation(AnimationCurve.Spring, scale)
.animation(AnimationCurve.Spring, rotation)
```

Pass a `State<Float>` reference to visual effect modifiers for dynamic binding. Type-checked at compile time. The `.animation()` modifier takes an `AnimationCurve` enum value that tells SwiftUI which curve to use when that `State<Float>` reference changes &mdash; no matter where the change comes from.

### Mutations Are Plain Closures

```haxe
new Button("Spin", () -> rotation.value += 90)
```

The action just sets `rotation.value`. Because the card declares
`.animation(AnimationCurve.Spring, rotation)`, SwiftUI interpolates the rotation
smoothly. Animation is a property of the *view*, not of the mutation.

### Transitions

```haxe
new ConditionalView(showDetail,
    detailView.transition("slide"),
    placeholder.transition("opacity")
)
```

`.transition()` defines how a view enters and exits. It only animates when the state
that drives the `ConditionalView` is bound to an `.animation` on the enclosing
container &mdash; here the outer `VStack` carries `.animation(AnimationCurve.Spring, showDetail)`.

### How They Work Together

1. **Action closures** &mdash; mutate state (`rotation.value += 90`)
2. **View bindings** &mdash; `.scaleEffect(scale)` reads the `State<Float>` field (type-checked)
3. **Animation curve** &mdash; `.animation(AnimationCurve.Spring, scale)` declares which state animates the view and HOW
4. **Transitions** &mdash; `.transition("slide")` specifies enter/exit behavior

All can be combined on the same view for complex animated interactions.

## Run It

```bash
cd examples/animations
haxelib run sui run macos
```
