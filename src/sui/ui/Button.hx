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
@:node("Button")
class Button extends View {
    @:prop public var label:String;
    public var labelView:Null<View>;
    /** The act itself: it crosses as a key, never as this closure. **/
    @:action("onClick") public var action:Null<() -> Void>;

    /**
        How much it stands out (`nui.Presentation`): `primary` -- the act the
        screen is for, prominent in the accent; `plain` -- no chrome, for a
        row's secondary acts; `check` -- a round tick-off mark whose label is
        spoken, not shown. A hint: anything else is an ordinary button.
    **/
    @:prop public var style:Null<String>;

    /** For `style="check"`: whether it is drawn ticked. The application's to say. **/
    @:prop public var checked:Bool;

    /**
        A name from `nui.Icons`, drawn beside the label -- or alone in a
        toolbar, which shows the icon and keeps the label as the tooltip and
        the spoken name. Markup could not give one: the canon has it and this
        declaration did not.
    **/
    @:prop public var icon:Null<String>;

    public function new(label:String, ?action:() -> Void, ?style:String, checked:Bool = false, ?icon:String) {
        super();
        this.viewType = "Button";
        this.label = label;
        this.action = action;
        this.style = style;
        this.checked = checked;
        this.icon = icon;
        if (icon != null && icon != "") properties.set("icon", icon);
    }

    /** Create a button with a custom view label. **/
    public static function withView(labelView:View, ?action:() -> Void):Button {
        var btn = new Button("", action);
        btn.labelView = labelView;
        return btn;
    }
}
