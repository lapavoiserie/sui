import mui.macros.Markup.ui;

/** A misspelt attribute. The schema has to name it and list what it accepts. **/
class BadAttr {
	static function main() {
		var t = ui(<Toggle label="Muet" isOn={false} onTogle={v -> {}}/>);
	}
}
