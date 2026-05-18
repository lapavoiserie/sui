package sui.ui;

import sui.View;

/**
    A rectangular shape primitive. Maps to SwiftUI's `Rectangle`.

    Like all SwiftUI shapes, it has no intrinsic size — give it one
    via `.frame(...)` or rely on the parent layout to size it.
    Fill with `.foregroundColor(...)` or `.foregroundHex(...)`.

    ```haxe
    new Rectangle()
        .frame(100, 50)
        .foregroundColor(ColorValue.Blue)
    ```
**/
@:swiftView("Rectangle")
class Rectangle extends View {
    public function new() {
        super();
        this.viewType = "Rectangle";
    }
}
