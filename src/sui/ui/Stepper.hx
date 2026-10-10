package sui.ui;

import sui.View;

/**
    An increment/decrement control. Maps to SwiftUI's `Stepper`.

    ```haxe
    new Stepper("Quantity", "quantity", 1, 10)
    ```

    Canon: `Stepper` carries `label`, an `Int` `value` with `onValue`, `min`,
    `max` and `step` (optional, 1). The bounds are part of what the value
    MEANS -- an interval of zero weeks is not a shorter interval, it is no
    interval -- so a backend clamps to them rather than treating them as a
    hint. Like every two-way control here, the cell crosses by NAME.
**/
@:node("Stepper")
@:swiftView("Stepper")
class Stepper extends View {
    @:prop public var label:String;
    @:cell("value", "onValue", "Int") public var valueBinding:String;
    @:prop("min") public var minValue:Int;
    @:prop("max") public var maxValue:Int;
    @:prop public var step:Int;

    public function new(@:swiftLabel("_") label:String, @:swiftLabel("value") @:swiftBinding valueBinding:String,
                        @:swiftLabel("in") minValue:Int, @:swiftLabel("_") maxValue:Int, step:Int = 1) {
        super();
        this.viewType = "Stepper";
        this.label = label;
        this.valueBinding = valueBinding;
        this.minValue = minValue;
        this.maxValue = maxValue;
        this.step = step < 1 ? 1 : step;
    }
}
