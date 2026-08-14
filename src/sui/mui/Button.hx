package sui.mui;


/**
	`sui`'s conformance for `mui.ui.Button`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class Button extends sui.ui.Button {
    public function new(label:String, ?action:() -> Void) {
        super(label, action);
    }
}
