import mui.macros.Markup.ui;

/** A screen's commands, from markup. See `check.sh`. **/
class Toolbars {
	static function main() {
		var bar:sui.ui.Toolbar = cast ui(<Toolbar title="Aujourd'hui">
			<Button label="Actualiser"/>
			<Button label="Nouvelle tâche"/>
		</Toolbar>);
		Sys.println('toolbar: ${bar.title} ' + [for (c in bar.children) Type.getClassName(Type.getClass(c))].join(","));
	}
}
