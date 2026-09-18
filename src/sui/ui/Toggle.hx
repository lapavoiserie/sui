package sui.ui;

import sui.View;

/**
    A toggle switch control.
    Maps to SwiftUI's `Toggle`.

    The `isOnBinding` parameter is the name of a `@State` Bool variable to bind to.
**/
@:swiftView("Toggle")
@:node("Toggle")
class Toggle extends View {
    @:prop public var label:String;
    // A NAME, not a cell: sui's state lives on the Swift side and is reached
    // through a registry, so the type says String and the kind is said here.
    @:cell("isOn", "onToggle", "Bool") public var isOnBinding:String;

    public function new(@:swiftLabel("_") label:String, @:swiftLabel("isOn") @:swiftBinding isOnBinding:String) {
        super();
        this.viewType = "Toggle";
        this.label = label;
        this.isOnBinding = isOnBinding;
    }
}
