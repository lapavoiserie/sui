package sui.mui;

/**
	`sui`'s conformance for `mui.ui.Icon`: a name from the shared vocabulary,
	drawn as the SF Symbol the renderer maps it to (`SuiIcons` in
	`DynamicView.swift`), coloured like text.

	```haxe
	new Icon(Mic)
	new Icon(SpeakerOff, "Monitor muted")
	```
**/
class Icon extends sui.View {
	public function new(name:mui.ui.IconName, ?label:String) {
		super();
		viewType = "Icon";
		properties.set("name", (name : String));
		if (label != null && label != "") properties.set("label", label);
	}
}
