package sui.mui;


/**
	`sui`'s conformance for `mui.ui.VStack`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class VStack extends sui.ui.VStack {
    public function new(content:Array<sui.View>, ?spacing:Float) {
        super(null, spacing, content);
    }
}
