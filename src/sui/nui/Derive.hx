package sui.nui;

#if macro
import haxe.macro.Expr.Field;
#end

/**
	Describing, written by `sui`'s declarations rather than by hand.

	Only that direction: SwiftUI draws, so nothing here ever makes a control out
	of a node. See `nui.macros.Derive` for the shared part, and
	`sui.nui.Vocabulary` for what is `sui`'s own — chiefly that its cells are
	known by NAME, state living on the Swift side.
**/
class Derive {
	#if macro
	/** Build `sui.nui.Derived`'s describers from what the controls declare. **/
	public static function build():Array<Field>
		return nui.macros.Derive.build(sui.nui.Vocabulary.DIALECT);
	#end
}
