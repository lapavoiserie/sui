import mui.macros.Markup.ui;

/** `ui(<VStack>…)` compiled against `sui`'s own declarations. **/
class MarkupCheck {
	static function main() {
		var sources = ["Caméra", "Pupitre"];
		var tree = ui(<VStack spacing={8.0}>
			<Text text="Régie"/>
			<Toggle label="Muet" isOn={false} onToggle={v -> {}}/>
			<Slider value={0.5} min={0.0} max={1.0} onValue={v -> {}}/>
			{[for (s in sources) ui(<Text text={s}/>)]}
		</VStack>);
		Sys.println(tree.type == "VStack" && tree.children.length == 5
			? "ok   a panel written in markup compiles against sui's declarations"
			: "FAIL " + tree.type + " with " + tree.children.length + " children");
		Sys.exit(tree.type == "VStack" && tree.children.length == 5 ? 0 : 1);
	}
}
