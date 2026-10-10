package sui.ui;

import sui.View;

/**
    A list whose order the person sets by hand: each row is picked up by its
    handle and dropped where it should go, or moved a step at a time from its
    context menu.

    ```haxe
    ui(<ReorderList onMove={(from, to) -> move(from, to)} moveUpLabel="Monter" moveDownLabel="Descendre">
        {[for (m in members) row(m)]}
    </ReorderList>)
    ```

    Canon: `ReorderList` carries its rows as children, `onMove(from, to)` --
    the row at `from` should end up at `to`, counted in the list as it is --
    and `moveUpLabel` / `moveDownLabel`, the application's words for the
    one-step moves. It reports; the application moves the row in its data.
**/
@:node("ReorderList")
@:content("content")
class ReorderList extends View {
    /** The move, as the renderer calls it. **/
    public var moveTo:Null<(Int, Int) -> Void>;
    /** The same move as the canon carries it over a wire: `"from,to"`. **/
    @:action("onMove") public var move:Null<String -> Void>;
    @:prop public var moveUpLabel:Null<String>;
    @:prop public var moveDownLabel:Null<String>;

    public function new(?move:(Int, Int) -> Void, ?moveUpLabel:String, ?moveDownLabel:String, content:Array<View>) {
        super();
        this.viewType = "ReorderList";
        this.moveTo = move;
        this.move = move == null ? null : (both:String) -> {
            var parts = both.split(",");
            var from = parts.length == 2 ? Std.parseInt(parts[0]) : null;
            var to = parts.length == 2 ? Std.parseInt(parts[1]) : null;
            if (from != null && to != null) move(from, to);
        };
        this.moveUpLabel = moveUpLabel;
        this.moveDownLabel = moveDownLabel;
        this.children = content == null ? [] : content;
    }
}
