package sui.ui;

import sui.View;

/**
    A drop-down menu containing buttons (or nested menus / dividers).
    Maps to SwiftUI's `Menu`.

    The typical use case is a toolbar dropdown — clicking the label
    opens a popover with the actions. On macOS it adopts the system
    `NSMenu` look; on iOS it's a popover sheet.

    ```haxe
    new Menu("Actions", [
        new Button("New", null, newAction),
        new Button("Open…", null, openAction),
        new Button("Delete", null, deleteAction),
    ])
    ```

    `Menu`s can be nested for sub-menus.
**/
@:swiftView("Menu")
class Menu extends View {
    public var label:String;

    public function new(@:swiftLabel("_") label:String, content:Array<View>) {
        super();
        this.viewType = "Menu";
        this.label = label;
        this.children = content;
    }
}
