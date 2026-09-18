package sui.ui;

import sui.View;

/**
    A view that arranges its children horizontally.
    Maps to SwiftUI's `HStack`.
**/
@:node("HStack")
@:content("content")
class HStack extends View {
    @:prop public var spacing:Null<Float>;
    public var alignment:VerticalAlignment;

    public function new(?alignment:VerticalAlignment, ?spacing:Float, content:Array<View>) {
        super();
        this.viewType = "HStack";
        this.alignment = alignment != null ? alignment : VerticalAlignment.Center;
        this.spacing = spacing;
        this.children = content;
    }
}

enum VerticalAlignment {
    Top;
    Center;
    Bottom;
    FirstTextBaseline;
    LastTextBaseline;
}
