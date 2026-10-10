import mui.macros.Markup.ui;

/** A stack's canonical `alignment`, from markup. See `check.sh`. **/
class Stacks {
	static function main() {
		var v:sui.ui.VStack = cast ui(<VStack alignment="leading"><Text text="a"/></VStack>);
		var h:sui.ui.HStack = cast ui(<HStack alignment="top"><Text text="b"/></HStack>);
		var plain:sui.ui.VStack = cast ui(<VStack><Text text="c"/></VStack>);
		Sys.println('stacks: ${v.alignment} ${h.alignment} ${plain.alignment}');
	}
}
