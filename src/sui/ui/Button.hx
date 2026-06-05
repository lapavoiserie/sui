package sui.ui;

import sui.View;

/**
    A control that initiates an action.
    Maps to SwiftUI's `Button`.

    The action is a plain Haxe closure. `StateMacro` wires it to the
    runtime store (`sui.state.Callbacks`) with a compile-time id, and
    the generated Swift dispatches `HaxeBridgeC.invokeAction(id)` (or
    `invokeIndexedAction` inside a `ForEach` row template).

    ```haxe
    new Button("+", () -> count.value++)
    new Button("Login", MyApp.startLogin)
    ```
**/
class Button extends View {
    public var label:String;
    public var labelView:Null<View>;
    public var action:Null<() -> Void>;

    public function new(label:String, ?action:() -> Void) {
        super();
        this.viewType = "Button";
        this.label = label;
        this.action = action;
    }

    /** Create a button with a custom view label. **/
    public static function withView(labelView:View, ?action:() -> Void):Button {
        var btn = new Button("", action);
        btn.labelView = labelView;
        return btn;
    }
}
