import mui.macros.Markup.ui;

/** A ProgressView's value, from markup. See `check.sh`. **/
class Progress {
	static function main() {
		var bar:sui.ui.ProgressView = cast ui(<ProgressView value={0.4}/>);
		var spinner:sui.ui.ProgressView = cast ui(<ProgressView/>);
		Sys.println('progress: ${bar.value} ${spinner.value}');
	}
}
