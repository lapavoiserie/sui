package sui.ui;

import sui.View;

/**
    A name from the shared vocabulary (`nui.Icons.NAMES`), drawn as the SF
    Symbol the renderer maps it to (`SuiIcons` in `DynamicView.swift`) and
    coloured like text.

    Canon: `Icon` carries `name` and an optional `label`, which is what a
    screen reader says; absent, it says the name. A name the renderer does not
    map draws nothing; `sui.mui.Icon`, the typed door, takes a
    `mui.ui.IconName` so a misspelt name there is a compile error.
**/
@:node("Icon")
class Icon extends View {
    @:prop public var name:String;
    @:prop public var label:Null<String>;

    public function new(name:String, ?label:String) {
        super();
        this.viewType = "Icon";
        this.name = name;
        this.label = label;
        properties.set("name", name);
        if (label != null && label != "") properties.set("label", label);
    }
}
