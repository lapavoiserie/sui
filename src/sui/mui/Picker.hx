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
		// The rows and the index are `sui.ui.Picker`'s own shape now -- it took
		// `Array<View>` and built nothing, so this class built the rows and set
		// the mode. Both moved down when that class was declared.
		super(label, selection.unwrap(), options);
	}
}
