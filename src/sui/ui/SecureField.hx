package sui.ui;

import sui.View;

/**
   A password input field that hides user input.
   Maps to SwiftUI's `SecureField`.

   The `textBinding` parameter is the name of a `@State` String variable to bind to.
**/
@:swiftView("SecureField")
@:node("SecretInput")
class SecureField extends View {
    @:prop public var placeholder:String;
    @:cell("text", "onText", "String") public var textBinding:String;

    public function new(@:swiftLabel("_") placeholder:String, @:swiftLabel("text") @:swiftBinding textBinding:String) {
        super();
        this.viewType = "SecureField";
        this.placeholder = placeholder;
        this.textBinding = textBinding;
    }
}
