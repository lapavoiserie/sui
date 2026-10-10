import mui.macros.Markup.ui;

/** `width` from markup becomes a Frame the renderer reads by position. See `check.sh`. **/
class Frames {
	static function main() {
		var cell:sui.View = ui(<Text text="12" width={70.0}/>);
		var m = cell.modifierChain[cell.modifierChain.length - 1];
		Sys.println('frame: ${Type.enumConstructor(m)} ${Type.enumParameters(m).map(Std.string).join(",")}');
	}
}
