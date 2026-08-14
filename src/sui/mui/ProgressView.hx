package sui.mui;


/**
	`sui`'s conformance for `mui.ui.ProgressView`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class ProgressView extends sui.ui.ProgressView {
    public function new(?label:String, ?value:Float) {
        super(label);
    }
}
