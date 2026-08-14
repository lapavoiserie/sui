package sui.mui;


/**
	`sui`'s conformance for `mui.ui.TextInput`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
@:swiftView("TextField")
class TextInput extends sui.ui.TextField {
    public function new(@:swiftLabel("_") placeholder:String,
                        @:swiftLabel("text") @:swiftBinding state:TextInputBinding) {
        super(placeholder, state.unwrap());
    }
}
