package sui.mui;

/**
	`sui`'s conformance for `mui.ui.Icon`: a name from the shared vocabulary,
	drawn as the SF Symbol the renderer maps it to (`SuiIcons` in
	`DynamicView.swift`), coloured like text.

	```haxe
	new Icon(Mic)
	new Icon(SpeakerOff, "Monitor muted")
	```

	The declared `sui.ui.Icon` does the work, so markup's `<Icon name="mic"/>`
	and this typed door build the same view.
**/
class Icon extends sui.ui.Icon {
	public function new(name:mui.ui.IconName, ?label:String) {
		super((name : String), label);
	}
}
