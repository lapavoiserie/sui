package sui.ui;

import sui.View;

/**
    A view that arranges its children vertically.
    Maps to SwiftUI's `VStack`.

    Canon: `alignment` (optional) is where the children sit across the
    stack -- `leading`, `center` (the default) or `trailing`. The parent's
    business, not a decoration on a child, which is why it is a property here
    and not a modifier.
**/
@:node("VStack")
@:content("content")
class VStack extends View {
    @:prop public var spacing:Null<Float>;
    public var alignment:HorizontalAlignment;
    /** The canonical `alignment`, as markup writes it. Wins over the enum when given. **/
    @:prop("alignment") public var align:Null<String>;

    public function new(?axis:HorizontalAlignment, ?spacing:Float, content:Array<View>, ?alignment:String) {
        super();
        this.viewType = "VStack";
        this.alignment = axis != null ? axis : switch (alignment == null ? "" : alignment.toLowerCase()) {
            case "leading": HorizontalAlignment.Leading;
            case "trailing": HorizontalAlignment.Trailing;
            default: HorizontalAlignment.Center;
        };
        this.align = alignment;
        this.spacing = spacing;
        this.children = content;
    }
}

enum HorizontalAlignment {
    Leading;
    Center;
    Trailing;
}
