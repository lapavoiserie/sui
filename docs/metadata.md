# Metadata

sui uses Haxe metadata annotations to control Swift code generation.

## @:expose

Exposes a static function to Swift as a named entry point (`HaxeBridgeC.functionName()`), so **hand-written Swift** can call it by name. This is an advanced escape hatch &mdash; most bridging is **automatic** via action closures, `@:state` updates, and lifecycle handlers.

```haxe
@:expose
public static function greet(name:String):String {
    return 'Hello, $name!';
}
```

```swift
// In your own Swift code:
let msg = HaxeBridgeC.greet("World")
```

**Calling it from an action (no @:expose needed):**
```haxe
public static function greet(name:String):String {
    return 'Hello, $name!';
}

// Ordinary Haxe call inside the closure — bridged automatically:
new Button("Greet", () -> result.value = greet("World"))
```

**Generated Swift (with @:expose):** `HaxeBridgeC.greet("World")`

**Requirements:**
- Must be `public static`
- Parameters and return types must be basic types (`String`, `Int`, `Float`, `Bool`)

`@:bridge` is accepted as a backward-compatible alias for `@:expose`.

See [Bridge](bridge.md) for full details.

## @:swiftBinding

Marks a `ViewComponent` property as a `@Binding` in the generated Swift struct.

```haxe
class StarRating extends ViewComponent {
    @:swiftBinding public var rating:Int;
    // ...
}
```

**Generated Swift:**
```swift
struct StarRating: View {
    @Binding var rating: Int
    // ...
}
```

Use on both the property declaration and the constructor parameter:

```haxe
public function new(@:swiftLabel("rating") @:swiftBinding rating:String) {
    super();
}
```

See [Binding](state/binding.md) and [Components](components.md).

## @:swiftLabel

Controls the argument label in generated Swift function/initializer calls.

```haxe
public function new(
    @:swiftLabel("title") title:String,
    @:swiftLabel("subtitle") subtitle:String
) {
    super();
    this.title = title;
    this.subtitle = subtitle;
}
```

**Generated Swift:** `InfoCard(title: "Hello", subtitle: "World")`

Without `@:swiftLabel`, parameters use positional arguments.

## @:swiftName

Overrides the generated Swift name for a function or type.

```haxe
@:swiftName("calculateTotal")
public static function calc(items:Array<Int>):Int {
    // ...
}
```

## @:swiftView

References a SwiftUI View struct by name. Use this to wrap a native SwiftUI view (defined in your `swift/` directory) so it can be used from Haxe.

```haxe
// swift/RatingStars.swift defines: struct RatingStars: View { let count: Int; ... }

@:swiftView("RatingStars")
class RatingStars extends View {
    public var count:Int;
    public function new(@:swiftLabel("count") count:Int) {
        super();
        this.count = count;
    }
}

// Usage in body():
new RatingStars(5)
```

**Generated Swift:** `RatingStars(count: 5)`

No Swift struct is generated for `@:swiftView` classes &mdash; it references your existing native implementation. Also applied automatically to `ViewComponent` subclasses.

See [Native Extensions](native-extensions.md) for full details.

## Summary

| Metadata | Target | Purpose |
|----------|--------|---------|
| `@:expose` | Static function | Expose named function to Swift (most bridging is automatic) |
| `@:state` | App field | Declare reactive state (`@:state var count:Int = 0`) |
| `@:swiftBinding` | Component property / constructor param | Generate `@Binding var` |
| `@:swiftLabel` | Constructor parameter | Set Swift argument label |
| `@:swiftName` | Function / type | Override generated Swift name |
| `@:swiftView` | Class | Reference a native SwiftUI View by name |
