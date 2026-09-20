import mui.macros.Markup.ui;

/** Markup builds sui's own controls. See `tests/markup-views/check.sh`. **/
class SuiMarkup {
	static function main() {
		var lit = new sui.state.State(true, "lit");
		var screen:sui.View = ui(<VStack spacing={8}>
			<Text text="built by sui itself"/>
			<Toggle label="lit" isOn={lit}/>
		</VStack>);
		var toggle:sui.ui.Toggle = cast screen.children[1];
		Sys.println("built: " + Type.getClassName(Type.getClass(screen))
			+ " | toggle bound to: " + toggle.isOnBinding
			+ " | label: " + toggle.label);
	}
}
