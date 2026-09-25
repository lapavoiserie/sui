package sui.ui;

import sui.View;

/**
    A choice among options. Maps to SwiftUI's `Picker`.

    ## Its options are DATA

    The canon states the shape -- `label`, one `Text` child per option, and a
    selection -- and carries the options as an array of strings
    (`@:children("Text", "text")`). This class took `Array<View>` instead, so
    it could not be declared: a declaration would have described something
    that was not there, and `<Picker>` was refused for this backend while
    `sui.mui.Picker` had been building exactly these rows all along.

    The rows are still `Text` children on the node -- that is what
    `DynamicView.swift` reads (`child.textContent`) and what `sui.nui.Describe`
    reports -- they are simply built here instead of by the caller.

    `rows` is the old shape, for a picker whose children a caller has already
    made. It is what `App.hx`'s example and `examples/closure-foreach` use.

    ## The selection is an index

    `selectedIndex`, as the canon speaks it and as `sui.mui.Picker` already
    declared with `selectionMode = "index"`. The cell crosses by NAME, like
    every two-way control here.
**/
@:node("Picker")
@:swiftView("Picker")
class Picker extends View {
    @:prop public var label:String;

    @:cell("selectedIndex", "onSelect", "Int") public var selectionBinding:String;

    /** The rows, as text. See the class doc. **/
    @:children("Text", "text") public var options:Array<String>;

    public function new(@:swiftLabel("_") label:String,
            @:swiftLabel("selection") @:swiftBinding selectionBinding:String,
            options:Array<String>) {
        super();
        this.viewType = "Picker";
        this.label = label;
        this.selectionBinding = selectionBinding;
        this.options = options == null ? [] : options;
        this.children = [for (option in this.options) new Text(option)];
        // The canon speaks positions; the renderer tags each row with its own.
        properties.set("selectionMode", "index");
    }

    /**
        A picker whose rows the caller built, and whose cell holds the chosen
        row's TEXT rather than its position -- what a SwiftUI `.tag(name)`
        usually stores. The shape this class had before it could be declared.
    **/
    public static function rows(label:String, selectionBinding:String, content:Array<View>):Picker {
        var picker = new Picker(label, selectionBinding, []);
        picker.children = content;
        picker.properties.remove("selectionMode");
        return picker;
    }
}
