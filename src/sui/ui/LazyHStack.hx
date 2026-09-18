package sui.ui;

import sui.View;
// The alignment enum lives in HStack's module, and this never imported it:
// LazyHStack has not compiled since it was written, and nothing forced it to
// until the declarations scanned the package.
import sui.ui.HStack.VerticalAlignment;

/**
    A lazy horizontal stack that only renders visible children.
    Maps to SwiftUI's `LazyHStack`. Same API as `HStack`.
**/
class LazyHStack extends View {
    public function new(?alignment:VerticalAlignment, ?spacing:Float, ?content:Array<View>) {
        super();
        this.viewType = "LazyHStack";
    }
}
