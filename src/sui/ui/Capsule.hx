package sui.ui;

import sui.View;

/**
    A capsule (stadium / pill) shape primitive — like a rectangle
    with fully rounded short edges. Maps to SwiftUI's `Capsule`.

    ```haxe
    new Capsule()
        .frame(100, 24)
        .foregroundColor(ColorValue.Accent)
    ```
**/
@:swiftView("Capsule")
class Capsule extends View {
    public function new() {
        super();
        this.viewType = "Capsule";
    }
}
