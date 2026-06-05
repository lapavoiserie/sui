# Binding

Bindings provide a two-way connection to a state variable. They're how child components read and write parent state.

## In SwiftUI Terms

| Haxe | SwiftUI |
|------|---------|
| `@:state var value:T` in parent | `@State var value: T` |
| `@:swiftBinding` in component | `@Binding var value: T` |

## Using Bindings with ViewComponent

Mark a component property with `@:swiftBinding` to generate a `@Binding` property in Swift:

```haxe
class StarRating extends ViewComponent {
    public var label:String;
    @:swiftBinding public var rating:Int;

    public function new(
        @:swiftLabel("label") label:String,
        @:swiftLabel("rating") @:swiftBinding rating:String
    ) {
        super();
        this.label = label;
    }

    override function body():View {
        return new HStack([
            new Text(label).font(FontStyle.Headline),
            new Spacer(),
            Text.bind('${rating} / 5')
                .foregroundColor(ColorValue.Orange)
        ]);
    }
}
```

Use it in a parent app:

```haxe
class MyApp extends App {
    @:state var movieRating:Int = 3;

    public function new() {
        super();
    }

    override function body():View {
        return new VStack([
            new StarRating("Movie:", "movieRating"),  // passes binding to state
            new Button("+", () -> movieRating.value++)
        ]);
    }
}
```

When the parent changes `movieRating`, the `StarRating` component updates automatically. If the component modifies `rating`, the parent's state updates too.

## Binding Class

The `Binding<T>` class provides programmatic binding from Haxe:

```haxe
// Create from an existing State
var binding = Binding.fromState(myState);

// Create with custom getter/setter
var binding = new Binding<String>(
    () -> myState.value,
    (v) -> myState.value = v
);
```

**Methods:**

| Method | Description |
|--------|-------------|
| `Binding.fromState(state)` | Create a binding from a `@:state` variable |
| `.value` | Read/write the bound value |

## Built-in Binding Parameters

Many views accept binding parameters as strings (the state variable name):

```haxe
new TextField("Name", "username")     // binds to @State var username
new Toggle("Dark Mode", "isDark")     // binds to @State var isDark
new Slider("vol", 0, 100)            // binds to @State var vol
new Picker("Color", "selected", [...]) // binds to @State var selected
```

These string parameters reference `@State` variables by name.
