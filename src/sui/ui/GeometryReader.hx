package sui.ui;

import sui.View;

/**
    Reports its parent-proposed size to its content via a SwiftUI
    `GeometryProxy`. Maps to SwiftUI's `GeometryReader`.

    Unlike most layout views, `GeometryReader` *claims the full
    space* proposed by its parent — children inside it are
    positioned in that space (default `.topLeading`). This makes it
    ideal for things like a "now" line that needs to know the
    rendered height of its container, or any view that wants to
    position itself by fractions of the parent.

    Inside a `GeometryReader`, the `.proportionalOffset(x, y)`
    modifier interprets its arguments as `0…1` fractions of the
    parent's measured size, so layout-precise positioning doesn't
    need any compile-time pixel constants.

    ```haxe
    new GeometryReader(
        new Rectangle()
            .frame(null, 2)
            .foregroundColor(ColorValue.Red)
            // Move down by `nowMinuteFrac` × measured height.
            .proportionalOffset(0.0, nowMinuteFrac)
    )
    ```

    `GeometryReader` reports through a Swift identifier named
    `proxy`; `.proportionalOffset` reads `proxy.size.width` and
    `proxy.size.height` directly, so the modifier must live inside
    a `GeometryReader` (it won't compile in a standalone view).
**/
@:swiftView("GeometryReader")
class GeometryReader extends View {
    public function new(content:View) {
        super();
        this.viewType = "GeometryReader";
        this.children = [content];
    }
}
