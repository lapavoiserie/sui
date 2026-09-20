import mui.macros.Markup.ui;

/**
	A decoration this backend cannot draw on one of its views.

	`sui`'s modifiers take a `ColorValue` and this backend converts only the
	other way, so a role written here has no door into a view. That is
	knowable while compiling, and knowable means refused -- not traced, and
	not drawn as something else.
**/
class BadDecoration {
	static function main() {
		var screen:sui.View = ui(<VStack backgroundColor={nui.Color.role(Surface)}/>);
		Sys.println(Type.getClassName(Type.getClass(screen)));
	}
}
