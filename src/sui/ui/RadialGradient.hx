package sui.ui;

import sui.View;

/**
    A radial gradient — colours laid out in concentric rings from a
    centre point. Maps to SwiftUI's `RadialGradient`.

    ```haxe
    new RadialGradient(
        [ColorValue.Yellow, ColorValue.Red],
        "center",
        0,
        100
    )
    ```

    `center` is one of the unit-point strings (`"center"`,
    `"top"`, `"topLeading"`, …). `startRadius` / `endRadius` are
    in points.
**/
@:swiftView("RadialGradient")
class RadialGradient extends View {
    public var colors:Array<ColorValue>;
    public var center:String;
    public var startRadius:Float;
    public var endRadius:Float;

    public function new(colors:Array<ColorValue>, center:String, startRadius:Float, endRadius:Float) {
        super();
        this.viewType = "RadialGradient";
        this.colors = colors;
        this.center = center;
        this.startRadius = startRadius;
        this.endRadius = endRadius;
    }
}
