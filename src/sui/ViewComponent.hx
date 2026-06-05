package sui;

/**
    Base class for reusable view components.
    Extend this class and override `body()` to create a component
    that generates a separate SwiftUI struct.

    Properties become Swift struct fields:
    - Regular fields → `let` properties
    - Fields with `@:binding` → `@Binding var` properties

    Example:
    ```haxe
    class StarRating extends ViewComponent {
        public var label:String;
        @:binding public var rating:Int;

        override function body():View {
            return new HStack([
                new Text(label),
                Text.withState("{rating} stars")
            ]);
        }
    }

    // Usage in parent:
    new StarRating("Movie:", "userRating")
    ```
**/
@:autoBuild(sui.macros.StateMacro.build())
class ViewComponent extends View {
    override public function body():View {
        return new View();
    }
}
