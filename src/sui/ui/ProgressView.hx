package sui.ui;

import sui.View;

/**
    A loading indicator. Maps to SwiftUI's `ProgressView`.

    Spinner (indeterminate):
    ```haxe
    new ProgressView()
    new ProgressView("Loading...")
    ```

    Bar (determinate):
    ```haxe
    new ProgressView("Downloading", "progress", 100.0)
    ```
**/
@:swiftView("ProgressView")
@:node("ProgressView")
class ProgressView extends View {
    @:prop public var label:Null<String>;
    public var valueBinding:String;
    public var total:Float;

    /**
        The fraction to show, when it is a value rather than a binding.

        The canon's `ProgressView` carries its progress as a number between
        zero and one, and `DynamicView.swift` has read it that way for as long
        as trees have arrived over the wire (`node.number("value")`). Only the
        Haxe side had nothing to put it in, so markup could not write one.
    **/
    @:prop public var value:Null<Float>;

    public function new(@:swiftLabel("_") ?label:String, @:swiftLabel("value") @:swiftBinding ?valueBinding:String, @:swiftLabel("total") ?total:Float) {
        super();
        this.viewType = "ProgressView";
        this.label = label;
        this.valueBinding = valueBinding;
        this.total = total != null ? total : 1.0;
    }
}
