import mui.macros.Markup.ui;

/** An order set by hand, from markup. See `check.sh`. **/
class Reorders {
	static function main() {
		var moved = "";
		var list:sui.ui.ReorderList = cast ui(<ReorderList onMove={(from, to) -> moved = '$from>$to'}
				moveUpLabel="Monter" moveDownLabel="Descendre">
			<Text key="lou" text="Lou"/>
			<Text key="sam" text="Sam"/>
		</ReorderList>);
		list.moveTo(1, 0);
		var first = moved;
		list.move("0,1");
		moved = first + " " + moved;
		Sys.println('reorder: rows=${list.children.length} up=${list.moveUpLabel} down=${list.moveDownLabel} moved=$moved');
	}
}
