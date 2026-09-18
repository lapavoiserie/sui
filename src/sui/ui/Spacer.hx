package sui.ui;

import sui.View;

/**
    A flexible space that expands along the major axis of its containing stack.
    Maps to SwiftUI's `Spacer`.
**/
@:node("Spacer")
class Spacer extends View {
    public var minLength:Null<Float>;

    public function new(?minLength:Float) {
        super();
        this.viewType = "Spacer";
        this.minLength = minLength;
    }
}
