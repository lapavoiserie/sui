package sui.mui;


/**
	`sui`'s conformance for `mui.ui.Divider`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
// sui's SwiftGenerator falls through to genericViewToSwift for unknown types,
// which uses the class name as the Swift view name. "Divider" maps directly
// to SwiftUI's native Divider() view.
class Divider extends sui.View {
    public function new() {
        super();
        this.viewType = "Divider";
    }
}
