package sui.mui;


/**
	`sui`'s conformance for `mui.ui.Button`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class Button extends sui.ui.Button {
    public function new(label:String, ?action:() -> Void, ?icon:mui.ui.IconName) {
        // The icon beside the label, or alone in a toolbar: `sui.ui.Button`
        // declares the canon's `icon` now, so this façade passes it on instead
        // of recording the omission.
        super(label, action, null, false, icon == null ? null : (icon : String));
    }
}
