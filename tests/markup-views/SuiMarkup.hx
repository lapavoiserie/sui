import mui.macros.Markup.ui;

/** Markup builds sui's own controls. See `tests/markup-views/check.sh`. **/
class SuiMarkup {
	static function main() {
		var lit = new sui.state.State(true, "lit");
		var screen:sui.View = ui(<VStack spacing={8} padding={{top: 8.0, right: 8.0, bottom: 8.0, left: 8.0}} opacity={0.9} clip={true}>
			<Text text="built by sui itself"/>
			<Toggle label="lit" isOn={lit}/>
			<Text key="a" text="first row"/>
			<Text key={"b"} text="second row"/>
		</VStack>);
		var toggle:sui.ui.Toggle = cast screen.children[1];
		Sys.println("built: " + Type.getClassName(Type.getClass(screen))
			+ " | toggle bound to: " + toggle.isOnBinding
			+ " | label: " + toggle.label
			+ " | keys: " + screen.children[2].key + "," + screen.children[3].key);
	}
}
