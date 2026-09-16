package sui.mui;

/**
	`sui`'s conformance for `mui.ui.Picker`: a SwiftUI `Picker` whose options
	are its children and whose selection is an **index**.

	`sui.ui.Picker` binds the text of the chosen row, which is what a SwiftUI
	`.tag(name)` usually stores. The mui contract speaks positions -- the same
	`selectedIndex` a received tree carries and a WinUI combo box reports -- so
	this one says so with `selectionMode = "index"`, and the renderer tags each
	row with its position.
**/
@:swiftView("Picker")
class Picker extends sui.ui.Picker {
	public function new(@:swiftLabel("_") label:String, options:Array<String>,
			@:swiftLabel("selection") @:swiftBinding selection:PickerBinding) {
		super(label, selection.unwrap(), [for (option in options) new sui.ui.Text(option)]);
		properties.set("selectionMode", "index");
	}
}
