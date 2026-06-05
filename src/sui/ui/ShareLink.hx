package sui.ui;

import sui.View;

/**
    A button that triggers the system share sheet. Maps to SwiftUI's
    `ShareLink(item:)`.

    The `item` is what gets shared — for v1 this is always a `String`,
    which SwiftUI auto-detects as a URL when it parses as one, or as
    plain text otherwise. Passing an optional `label` lets you
    override the default share-arrow icon.

    ```haxe
    // Default UI (system share-arrow icon)
    new ShareLink("https://example.com")

    // Custom label
    new ShareLink("https://example.com", "Share this link")
    ```

    On macOS opens the system Share menu; on iOS / iPadOS / visionOS
    opens the activity controller (UIActivityViewController).
**/
@:swiftView("ShareLink")
class ShareLink extends View {
    public var item:String;
    public var label:Null<String>;

    public function new(@:swiftLabel("item") item:String, ?label:String) {
        super();
        this.viewType = "ShareLink";
        this.item = item;
        this.label = label;
    }
}
