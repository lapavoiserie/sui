import mui.macros.Markup.ui;

/**
	The controls declared for the desktop chores client, built from markup.
	Prints one line per control, read back by `check.sh`: the class markup
	built and what it carries.
**/
class Controls {
	static function main() {
		var interval = new sui.state.State(2, "interval");
		var due = new sui.state.State("2026-10-12", "due");
		var section = new sui.state.State(1, "section");
		var editing = new sui.state.State(false, "editing");
		var archiving = new sui.state.State(true, "archiving");
		var archived = false;
		var screen:sui.View = ui(<VStack>
			<Section title="Récurrence">
				<Text text="inside"/>
			</Section>
			<Divider/>
			<Icon name="mic" label="Micro"/>
			<Menu label="Actions">
				<Button label="Passer"/>
				<Divider/>
				<Button label="Réassigner"/>
			</Menu>
			<Stepper label="Toutes les" value={interval} min={1} max={999}/>
			<DateInput label="Première échéance" value={due} min="2026-01-01"/>
			<Tabs selectedIndex={section} style="sidebar">
				<Tab label="Aujourd'hui" icon="calendar"><Text text="today page"/></Tab>
				<Tab label="Tâches"><Text text="chores page"/></Tab>
				<Tab label="Répartition"><Text text="split page"/></Tab>
			</Tabs>
			<Sheet presented={editing} title="Nouvelle tâche"><Text text="form"/></Sheet>
			<ConfirmDialog presented={archiving} title="Archiver ?" confirmLabel="Archiver"
				cancelLabel="Annuler" destructive={true} onConfirm={() -> archived = true}/>
		</VStack>);
		for (child in screen.children) Sys.println(line(child));
		var dialog:sui.ui.ConfirmDialog = cast screen.children[screen.children.length - 1];
		dialog.action();
		Sys.println('confirm ran: $archived');

		// The selection and the presented flag decide SHAPE (which page, any
		// content at all), so building them must record a read of their cell:
		// that read is what turns a write into a rebuild.
		sui.runtime.ReadScope.begin();
		ui(<Tabs selectedIndex={section}><Tab label="a"><Text text="p"/></Tab></Tabs>);
		ui(<Sheet presented={editing}><Text text="f"/></Sheet>);
		Sys.println("structural: " + sui.runtime.ReadScope.end().join(","));
	}

	static function line(v:sui.View):String {
		var name = Type.getClassName(Type.getClass(v));
		return switch name {
			case "sui.ui.Section":
				var s:sui.ui.Section = cast v;
				'section: ${s.header} children=${s.children.length}';
			case "sui.ui.Divider": "divider";
			case "sui.ui.Icon":
				var i:sui.ui.Icon = cast v;
				'icon: ${i.name} label=${i.label}';
			case "sui.ui.Menu":
				var m:sui.ui.Menu = cast v;
				'menu: ${m.label} items=${[for (c in m.children) Type.getClassName(Type.getClass(c))].join(",")}';
			case "sui.ui.Stepper":
				var st:sui.ui.Stepper = cast v;
				'stepper: ${st.label} bound=${st.valueBinding} ${st.minValue}..${st.maxValue} step=${st.step}';
			case "sui.ui.DateInput":
				var d:sui.ui.DateInput = cast v;
				'date: ${d.label} bound=${d.valueBinding} min=${d.min} max=${d.max}';
			case "sui.ui.Tabs":
				var t:sui.ui.Tabs = cast v;
				'tabs: style=${t.style} bound=${t.selectionBinding} pages=' + [for (tab in t.children) tab.children.length].join(",");
			case "sui.ui.Sheet":
				var sh:sui.ui.Sheet = cast v;
				'sheet: ${sh.title} bound=${sh.presentedBinding} children=${sh.children.length}';
			case "sui.ui.ConfirmDialog":
				var c:sui.ui.ConfirmDialog = cast v;
				'confirm: ${c.title} bound=${c.presentedBinding} ${c.confirmLabel}/${c.cancelLabel} destructive=${c.destructive}';
			default: 'unexpected: $name';
		}
	}
}
