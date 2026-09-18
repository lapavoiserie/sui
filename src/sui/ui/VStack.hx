package sui.ui;

import sui.View;

/**
    A view that arranges its children vertically.
    Maps to SwiftUI's `VStack`.
**/
@:node("VStack")
@:content("content")
class VStack extends View {
    @:prop public var spacing:Null<Float>;
    public var alignment:HorizontalAlignment;

    public function new(?alignment:HorizontalAlignment, ?spacing:Float, content:Array<View>) {
        super();
        this.viewType = "VStack";
        this.alignment = alignment != null ? alignment : HorizontalAlignment.Center;
        this.spacing = spacing;
        this.children = content;
    }
}

enum HorizontalAlignment {
    Leading;
    Center;
    Trailing;
}
