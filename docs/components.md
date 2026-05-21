# Components

`ViewComponent` lets you create reusable views that generate separate SwiftUI structs.

## Creating a Component

Extend `ViewComponent` and override `body()`:

```haxe
import sui.ViewComponent;
import sui.View;
import sui.ui.*;

class InfoCard extends ViewComponent {
    public var title:String;
    public var subtitle:String;

    public function new(
        @:swiftLabel("title") title:String,
        @:swiftLabel("subtitle") subtitle:String
    ) {
        super();
        this.title = title;
        this.subtitle = subtitle;
    }

    override function body():View {
        return new VStack([
            new Text(title)
                .font(FontStyle.Title2)
                .bold(),
            new Text(subtitle)
                .font(FontStyle.Subheadline)
                .foregroundColor(ColorValue.Secondary)
        ])
        .padding()
        .background(ColorValue.Gray)
        .cornerRadius(12);
    }
}
```

Use it like any view:

```haxe
override function body():View {
    return new VStack([
        new InfoCard("Sui", "Build native apps in Haxe"),
        new InfoCard("Components", "Reusable views with @Binding")
    ]);
}
```

## Components with Binding

Use `@:swiftBinding` for two-way state binding:

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

Pass a state variable name to bind:

```haxe
@:state var movieRating:Int = 3;

// In body():
new StarRating("Movie:", "movieRating")
```

The component receives a `@Binding` to the parent's `@State` &mdash; changes flow both ways.

## How It Works

Each `ViewComponent` subclass generates a separate SwiftUI struct:

```swift
// Generated Swift
struct InfoCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack {
            Text(title).font(.title2).bold()
            Text(subtitle).font(.subheadline).foregroundColor(.secondary)
        }
        .padding()
        .background(Color.gray)
        .cornerRadius(12)
    }
}
```

Properties become struct fields. `@:swiftBinding` properties become `@Binding var` fields.

## Key Points

- One component per `.hx` file
- Use `@:swiftLabel` on constructor parameters to control Swift argument labels
- Use `@:swiftBinding` for two-way bindings
- Components can contain any views and modifiers
- Components can be nested inside other components
