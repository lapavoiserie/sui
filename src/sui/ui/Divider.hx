package sui.ui;

import sui.View;

/**
    A thin line between two groups. Maps to SwiftUI's `Divider`, which runs
    across a stack and between the items of a `Menu`.

    Canon: `Divider` carries nothing.
**/
@:node("Divider")
class Divider extends View {
    public function new() {
        super();
        this.viewType = "Divider";
    }
}
