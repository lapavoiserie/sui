package sui.ui;

import sui.View;

/**
    An angular (conic) gradient — colours laid out around a centre
    point, sweeping a full circle. Maps to SwiftUI's
    `AngularGradient`.

    ```haxe
    new AngularGradient(
        [ColorValue.Red, ColorValue.Orange, ColorValue.Yellow, ColorValue.Green, ColorValue.Blue, ColorValue.Purple, ColorValue.Red],
        "center"
    )
    ```

    `center` is one of the unit-point strings (`"center"`,
    `"top"`, `"topLeading"`, …).
**/
@:swiftView("AngularGradient")
class AngularGradient extends View {
    public var colors:Array<ColorValue>;
    public var center:String;

    public function new(colors:Array<ColorValue>, center:String) {
        super();
        this.viewType = "AngularGradient";
        this.colors = colors;
        this.center = center;
    }
}
