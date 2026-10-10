import mui.macros.Markup.ui;

/** A Button's style hint and `checked`, from markup. See `check.sh`. **/
class Buttons {
	static function main() {
		var save:sui.ui.Button = cast ui(<Button label="Enregistrer" style="primary"/>);
		var skip:sui.ui.Button = cast ui(<Button label="Passer" style="plain"/>);
		var tick:sui.ui.Button = cast ui(<Button label="Marquer la vaisselle comme faite" style="check" checked={true}/>);
		var plain:sui.ui.Button = cast ui(<Button label="Annuler"/>);
		Sys.println('buttons: ${save.style} ${skip.style} ${tick.style}/${tick.checked} ${plain.style}/${plain.checked}');
	}
}
