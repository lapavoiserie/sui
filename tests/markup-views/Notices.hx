import mui.macros.Markup.ui;

/** News, from markup. See `check.sh`. **/
class Notices {
	static function main() {
		var shown = new sui.state.State(true, "shown");
		var undone = false;
		var n:sui.ui.Notice = cast ui(<Notice presented={shown} message="Vaisselle faite" kind="success"
			actionLabel="Annuler" onAction={() -> undone = true} dismissLabel="Fermer"/>);
		n.action();
		Sys.println('notice: ${n.message} kind=${n.kind} act=${n.actionLabel} close=${n.dismissLabel} bound=${n.presentedBinding} undone=$undone');
	}
}
