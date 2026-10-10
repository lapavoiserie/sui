package sui.ui;

import sui.View;

/**
    A titled group of controls. Maps to SwiftUI's `Section`, which a `Form`
    draws as a grouped block and a plain stack as a heading over its rows.

    ```haxe
    new Section("Récurrence", [new Picker(...), new Stepper(...)])
    ```

    Canon: `Section` carries an optional `title` and its children.
**/
@:node("Section")
@:content("content")
class Section extends View {
    @:prop("title") public var header:Null<String>;

    public function new(?header:String, content:Array<View>) {
        super();
        this.viewType = "Section";
        this.header = header;
        this.children = content == null ? [] : content;
    }
}
