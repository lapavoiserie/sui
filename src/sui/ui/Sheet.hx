package sui.ui;

import sui.View;

/**
    A panel over the window, for a task that has to be finished or abandoned
    before going on: an edit form, a choice. Maps to SwiftUI's `.sheet`.

    ```haxe
    ui(<Sheet presented={editing_} title="Nouvelle tâche">
        <ChoreForm/>
    </Sheet>)
    ```

    Canon: `Sheet` carries `presented` (`Bool`) with `onPresented`, an
    optional `title`, and its content as children -- **only while
    presented**.

    ## Whether it is open is the application's

    Like a `Tabs` selection and unlike a `Disclosure`: the application opens
    it by writing `true`, and the person closing it (Escape, a click outside)
    writes `false` back through the same cell. Content an application has not
    presented is not in the tree, for the reason a closed tab's page is not:
    nothing to describe, project or leak. The cell is read as a dependency,
    so opening rebuilds the tree and the content exists when it is drawn.

    The node itself draws nothing where it stands -- the sheet hangs off the
    window -- so it can sit anywhere in a screen.
**/
@:node("Sheet")
@:content("content")
class Sheet extends View {
    @:cell("presented", "onPresented", "Bool") public var presentedBinding:String;
    @:prop public var title:Null<String>;

    public function new(presentedBinding:String, ?title:String, content:Array<View>) {
        super();
        this.viewType = "Sheet";
        this.presentedBinding = presentedBinding;
        this.title = title;
        var raw:Dynamic = sui.state.State.readByName(presentedBinding);
        var open = raw == true || Std.string(raw) == "true";
        this.children = open && content != null ? content : [];
    }
}
