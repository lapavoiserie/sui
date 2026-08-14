package sui.mui;


/**
	`sui`'s conformance for `mui.ui.SafeArea`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
@:muiSupport("none", "SwiftUI handles safe areas by default: nothing to apply")
class SafeArea extends sui.ui.VStack {
    public function new(content:Array<sui.View>) {
        // SwiftUI handles safe areas by default
        super(null, null, content);
        // SwiftUI's own default inset, which is what `.padding()` with no
        // number means -- deliberately not a figure written down here.
        padding();
    }

    /** Modifier form — returns this view unchanged (SwiftUI default). **/
    public function safeArea():sui.View {
        return this;
    }
}
