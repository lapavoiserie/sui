package sui.mui;

import mui.ui.TabItem;

/**
	`sui`'s conformance for `mui.ui.TabView`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class TabView extends sui.ui.TabView {
    public function new(tabs:Array<TabItem>) {
        super([for (t in tabs) {label: t.label, systemImage: "", content: t.content}]);
    }
}
