package sui.ui;

import sui.View;

/**
    A text input field.
    Maps to SwiftUI's `TextField`.

    The `textBinding` parameter is the name of a `@State` String variable to bind to.
**/
@:swiftView("TextField")
@:node("TextInput")
class TextField extends View {
    @:prop public var placeholder:String;
    @:cell("text", "onText", "String") public var textBinding:String;

    public function new(@:swiftLabel("_") placeholder:String, @:swiftLabel("text") @:swiftBinding textBinding:String) {
        super();
        this.viewType = "TextField";
        this.placeholder = placeholder;
        this.textBinding = textBinding;
    }
}
