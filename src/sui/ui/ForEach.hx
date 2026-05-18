package sui.ui;

import sui.View;

/**
    Iterates over a state array and generates a view for each element.
    Maps to SwiftUI's `ForEach`.

    Two call shapes, both compiled by the SwiftGenerator macro:

    **Closure form (preferred)** — the iteration parameter is a Haxe
    value, so references inside the body are type-checked at compile
    time and SwiftUI receives the right expression without you having
    to spell out the array subscript as a string. Modifiers like
    `Text(item)` and `.tag(item)` detect the item ref and emit the
    matching Swift expression.

    ```haxe
    new ForEach(colorOptions, item ->
        new Text(item).tag(item)
    )
    ```

    Generates:
    ```swift
    ForEach(0..<colorOptions.count, id: \.self) { item in
        Text("\(appState.colorOptions[item])")
            .tag(appState.colorOptions[item])
    }
    ```

    **Legacy form (kept for backward compatibility)** — pass the
    iteration variable name as a String and use string templating
    inside the body view (`Text.withState("{name[i]}")`).

    ```haxe
    new ForEach(todos, "i",
        Text.withState("{todos[i].title}")
    )
    ```
**/
class ForEach extends View {
    public var arrayName:Dynamic;
    public var itemName:String;
    public var itemView:View;
    /** Closure-form builder, captured at runtime so the type-system
        sees the param; the macro takes the typed-AST path instead. **/
    public var builder:Dynamic;

    /**
        @param arrayName State<Array<T>> field reference or string name of the @State array variable
        @param itemNameOrBuilder Either the iteration variable name (legacy form, takes a third argument) OR a `T -> View` closure that builds each row given the item value
        @param itemView View to render — only required for the legacy 3-arg form
    **/
    public function new(arrayName:Dynamic, itemNameOrBuilder:Dynamic, ?itemView:View) {
        super();
        this.viewType = "ForEach";
        this.arrayName = arrayName;
        if (itemView != null) {
            this.itemName = itemNameOrBuilder;
            this.itemView = itemView;
            this.children = [itemView];
        } else if (Reflect.isFunction(itemNameOrBuilder)) {
            // Closure form — the macro inspects the typed AST.
            this.builder = itemNameOrBuilder;
            this.itemName = "item";
            this.itemView = null;
            this.children = [];
        } else {
            // String itemName but no itemView — degenerate, kept for safety.
            this.itemName = itemNameOrBuilder;
            this.itemView = null;
            this.children = [];
        }
    }
}
