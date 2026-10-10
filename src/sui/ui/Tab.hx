package sui.ui;

import sui.View;

/**
    One labelled page of a `Tabs`. Its child is the page, and it has one only
    while it is the selected tab (see `Tabs`).

    Canon: `Tab` carries `label` and an optional `icon`, a name from
    `nui.Icons`.
**/
@:node("Tab")
@:content("content")
class Tab extends View {
    @:prop public var label:String;
    @:prop public var icon:Null<String>;

    public function new(label:String, ?icon:String, content:Array<View>) {
        super();
        this.viewType = "Tab";
        this.label = label;
        this.icon = icon;
        this.children = content == null ? [] : content;
    }
}
