package sui.ui;

import sui.View;

/**
    An ellipse shape primitive — fills the bounds of its container,
    so the aspect ratio is determined by `.frame(width, height)`.
    Maps to SwiftUI's `Ellipse`.

    ```haxe
    new Ellipse()
        .frame(100, 50)
        .foregroundColor(ColorValue.Purple)
    ```
**/
@:swiftView("Ellipse")
class Ellipse extends View {
    public function new() {
        super();
        this.viewType = "Ellipse";
    }
}
