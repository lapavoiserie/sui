package sui.ui;

import sui.View;

/**
    An expandable section. Maps to SwiftUI's `DisclosureGroup`.

    ```haxe
    new DisclosureGroup("Advanced Settings", [
        new Toggle("Debug Mode", "debugMode"),
        new Toggle("Verbose Logging", "verbose")
    ])
    ```
**/
@:node("Disclosure")
@:content("content")
class DisclosureGroup extends View {
    @:prop("title") public var label:String;
    public var content:Array<View>;

    public function new(label:String, content:Array<View>) {
        super();
        this.viewType = "DisclosureGroup";
        this.label = label;
        this.content = content;
    }
}
