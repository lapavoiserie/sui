import mui.macros.Markup.ui;

/**
	A decoration this backend cannot draw on one of its views.

	`flex` is a share of the space left over, and SwiftUI shares leftover
	space with spacers and layout priority rather than a share on the child.
	That is knowable while compiling, and knowable means refused -- not
	traced, and not drawn as something else.
**/
class BadDecoration {
	static function main() {
		var screen:sui.View = ui(<VStack flex={1.0}/>);
		Sys.println(Type.getClassName(Type.getClass(screen)));
	}
}
