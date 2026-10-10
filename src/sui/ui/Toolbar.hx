package sui.ui;

import sui.View;

/**
    A screen's commands, in the window's toolbar.

    ```haxe
    ui(<Toolbar title="Aujourd'hui">
        <Picker label="Espace" selectedIndex={workspace_}>{names}</Picker>
        <Button label="Nouvelle tâche" style="primary" onClick={add}/>
    </Toolbar>)
    ```

    Canon: `Toolbar` carries an optional `title` and its commands as children.
    On macOS the children go to the window's unified toolbar, after the
    title, and `title` is the window's title for this screen; the node draws
    nothing where it stands, so it can sit anywhere in the screen it belongs
    to. A screen that is not shown declares no toolbar, so a tab's commands
    leave with it.
**/
@:node("Toolbar")
@:content("content")
class Toolbar extends View {
    @:prop public var title:Null<String>;

    public function new(?title:String, content:Array<View>) {
        super();
        this.viewType = "Toolbar";
        this.title = title;
        this.children = content == null ? [] : content;
    }
}
