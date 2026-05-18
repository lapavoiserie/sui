package sui.ui;

import sui.View;

/**
    A linear gradient — colours laid out along a straight line
    between two unit points. Maps to SwiftUI's `LinearGradient`.

    ```haxe
    new LinearGradient(
        [ColorValue.Blue, ColorValue.Purple],
        "top",
        "bottom"
    )
    ```

    Common unit-point strings: `"top"`, `"bottom"`, `"leading"`,
    `"trailing"`, `"topLeading"`, `"topTrailing"`,
    `"bottomLeading"`, `"bottomTrailing"`, `"center"`.

    Like all gradients, has no intrinsic size — use `.frame(...)`
    or rely on the parent to size it. Often used as a `.background`
    or inside a `.foregroundColor` style.
**/
@:swiftView("LinearGradient")
class LinearGradient extends View {
    public var colors:Array<ColorValue>;
    public var startPoint:String;
    public var endPoint:String;

    public function new(colors:Array<ColorValue>, startPoint:String, endPoint:String) {
        super();
        this.viewType = "LinearGradient";
        this.colors = colors;
        this.startPoint = startPoint;
        this.endPoint = endPoint;
    }
}
