package sui.ui;

import sui.View;

/**
    One row of a form: a label, and the controls that answer it. Maps to
    SwiftUI's `LabeledContent`, whose label a `Form` puts in its label column.

    ```haxe
    ui(<Field label="Jours">
        <Toggle label="L" isOn={mo_} style="button"/>
        <Toggle label="M" isOn={tu_} style="button"/>
    </Field>)
    ```

    Canon: `Field` carries a `label` and its controls as children, side by
    side. Outside a `Form` it is its label followed by its controls.
**/
@:node("Field")
@:content("content")
class Field extends View {
    @:prop public var label:String;

    public function new(label:String, content:Array<View>) {
        super();
        this.viewType = "Field";
        this.label = label;
        this.children = content == null ? [] : content;
    }
}
