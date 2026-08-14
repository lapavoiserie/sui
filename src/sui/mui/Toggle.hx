package sui.mui;


/**
	`sui`'s conformance for `mui.ui.Toggle`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
@:swiftView("Toggle")
class Toggle extends sui.ui.Toggle {
    public function new(@:swiftLabel("_") label:String,
                        @:swiftLabel("isOn") @:swiftBinding state:ToggleBinding) {
        super(label, state.unwrap());
    }
}
