package sui.mui;


/**
	`sui`'s conformance for `mui.ui.Slider`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
@:swiftView("Slider")
class Slider extends sui.ui.Slider {
    public function new(@:swiftBinding state:SliderBinding, min:Float = 0.0, max:Float = 1.0) {
        super(state.unwrap(), min, max);
    }
}
