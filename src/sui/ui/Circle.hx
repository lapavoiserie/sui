package sui.ui;

import sui.View;

/**
    A circular shape primitive. Maps to SwiftUI's `Circle`.

    Fits inside the bounds of its container — give it a square
    `.frame(...)` for a true circle.

    ```haxe
    new Circle()
        .frame(20, 20)
        .foregroundColor(ColorValue.Red)
    ```
**/
@:swiftView("Circle")
class Circle extends View {
    public function new() {
        super();
        this.viewType = "Circle";
    }
}
