package sui.mui;


/**
	`sui`'s conformance for `mui.ui.Button`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
@:muiSupport("approx", "a SwiftUI Button here draws its label: no icon slot yet")
class Button extends sui.ui.Button {
    public function new(label:String, ?action:() -> Void, ?icon:mui.ui.IconName) {
        // `sui.ui.Button` has no icon slot yet, so the label is what is drawn.
        // The argument is accepted rather than refused -- an application writes
        // one view for six backends -- and the omission is recorded rather than
        // dropped in silence: `@:muiSupport` above puts the reason in the
        // matrix, beside the row. sui's dynamic renderer already draws the icon
        // of a RECEIVED Button; it is this façade's own control that has none.
        super(label, action);
    }
}
