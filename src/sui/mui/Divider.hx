package sui.mui;

/**
	`sui`'s conformance for `mui.ui.Divider`: the declared `sui.ui.Divider`,
	so the typed door and markup's `<Divider/>` build the same view.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`.
**/
class Divider extends sui.ui.Divider {
	public function new() {
		super();
	}
}
