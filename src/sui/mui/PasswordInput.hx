package sui.mui;


/**
	`sui`'s conformance for `mui.ui.PasswordInput`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. SwiftUI's own `SecureField`,
	which this backend has had since before the canon named the type — bound to
	the application's state like any field, and drawn masked.
**/
@:swiftView("SecureField")
class PasswordInput extends sui.ui.SecureField {
    public function new(@:swiftLabel("_") placeholder:String,
                        @:swiftLabel("text") @:swiftBinding state:TextInputBinding) {
        super(placeholder, state.unwrap());
    }
}
