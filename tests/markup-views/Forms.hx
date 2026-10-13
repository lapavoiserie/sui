import mui.macros.Markup.ui;

/** The rows of one entry, from markup. See `check.sh`. **/
class Forms {
	static function main() {
		var title = new sui.state.State("", "title");
		var sa = new sui.state.State(true, "sa");
		var form:sui.ui.Form = cast ui(<Form>
			<Section>
				<Field label="Quoi"><TextInput text={title} placeholder="Passer l'aspirateur"/></Field>
			</Section>
			<Section>
				<Field label="Jours"><Toggle label="S" isOn={sa} style="button" spokenLabel="samedi"/><Text text="samedi"/></Field>
			</Section>
		</Form>);
		var days:sui.ui.Field = cast form.children[1].children[0];
		var toggle:sui.ui.Toggle = cast days.children[0];
		Sys.println('form: sections=${form.children.length} field=${days.label} children=${days.children.length} toggle=${toggle.style} spoken=${toggle.spokenLabel} bound=${toggle.isOnBinding}');
	}
}
