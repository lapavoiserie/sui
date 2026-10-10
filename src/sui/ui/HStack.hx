package sui.ui;

import sui.View;

/**
    A view that arranges its children horizontally.
    Maps to SwiftUI's `HStack`.

    Canon: `alignment` (optional) is where the children sit across the
    stack -- `top`, `center` (the default) or `bottom`.
**/
@:node("HStack")
@:content("content")
class HStack extends View {
    @:prop public var spacing:Null<Float>;
    public var alignment:VerticalAlignment;
    /** The canonical `alignment`, as markup writes it. Wins over the enum when given. **/
    @:prop("alignment") public var align:Null<String>;

    public function new(?axis:VerticalAlignment, ?spacing:Float, content:Array<View>, ?alignment:String) {
        super();
        this.viewType = "HStack";
        this.alignment = axis != null ? axis : switch (alignment == null ? "" : alignment.toLowerCase()) {
            case "top": VerticalAlignment.Top;
            case "bottom": VerticalAlignment.Bottom;
            default: VerticalAlignment.Center;
        };
        this.align = alignment;
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
