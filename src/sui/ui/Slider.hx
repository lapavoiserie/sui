package sui.ui;

import sui.View;

/**
    A slider control for selecting a value from a range.
    Maps to SwiftUI's `Slider`.

    The `valueBinding` is the name of a `@State` Float/Double variable to bind to.
**/
@:node("Slider")
class Slider extends View {
    @:cell("value", "onValue", "Float") public var valueBinding:String;
    @:prop("min") public var rangeMin:Float;
    @:prop("max") public var rangeMax:Float;

    public function new(valueBinding:String, rangeMin:Float, rangeMax:Float) {
        super();
        this.viewType = "Slider";
        this.valueBinding = valueBinding;
        this.rangeMin = rangeMin;
        this.rangeMax = rangeMax;
    }
}
