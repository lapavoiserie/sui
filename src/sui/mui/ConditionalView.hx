package sui.mui;


/**
	`sui`'s conformance for `mui.ui.ConditionalView`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class ConditionalView extends sui.ui.ConditionalView {
    public function new(condition:sui.state.State<Bool>, thenView:sui.View, ?elseView:sui.View) {
        super(condition, thenView, elseView);
    }
}
