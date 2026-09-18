package sui.ui;

import sui.View;

/**
    A view that overlays its children on top of each other.
    Maps to SwiftUI's `ZStack`.
**/
@:node("ZStack")
@:content("content")
class ZStack extends View {
    public function new(?alignment:Alignment, content:Array<View>) {
        super();
        this.viewType = "ZStack";
        if (alignment != null)
            this.properties.set("alignment", alignment);
        this.children = content;
    }
}
