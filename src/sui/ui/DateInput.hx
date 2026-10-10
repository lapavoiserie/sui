package sui.ui;

import sui.View;

/**
    A calendar day, without a time and without a time zone.

    ```haxe
    new DateInput("First due", "firstDue")        // cell holds "2026-10-12"
    ```

    Canon: `DateInput` carries `label`, a `String` `value` in `YYYY-MM-DD`
    with `onValue`, and optional `min` / `max` in the same form.

    ## A civil day, not an instant

    `IsoDatePicker` binds an ISO-8601 *instant*, and an instant is a day only
    in some time zone. A chore due "the 12th" stored as midnight UTC is the
    11th on a screen in New York, and the one the household meant was neither
    -- it was the 12th, wherever anyone looks at it. So this control's value
    is the day itself, as text, and the renderer reads and writes it on a
    calendar pinned to UTC, where a day and its midnight cannot disagree.

    An empty or unreadable value shows today and is not written back until
    somebody picks a day: a control that silently filled in a date would be
    an edit nobody made.
**/
@:node("DateInput")
class DateInput extends View {
    @:prop public var label:String;
    @:cell("value", "onValue", "String") public var valueBinding:String;
    @:prop public var min:Null<String>;
    @:prop public var max:Null<String>;

    public function new(label:String, valueBinding:String, ?min:String, ?max:String) {
        super();
        this.viewType = "DateInput";
        this.label = label;
        this.valueBinding = valueBinding;
        this.min = min;
        this.max = max;
    }
}
