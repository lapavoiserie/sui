package sui.platform;

import sui.View;

/**
    macOS-specific views and functionality.
**/
class MacOS {
    /**
        Create a menu bar section for macOS apps.

        Never drawn: no renderer has a case for `MenuBar`, so this built a node
        nothing showed. A menu bar extra is a surface -- `@:surface(Status)`
        returning a `mui.surface.Labelled` -- and the application menus are
        `@:surface(Commands)`.
    **/
    @:deprecated("never drawn -- declare @:surface(Status) for a menu bar extra, @:surface(Commands) for menus")
    public static function menuBar(title:String, items:Array<MenuItem>):View {
        var view = new View();
        view.viewType = "MenuBar";
        view.properties.set("title", title);
        view.properties.set("items", items);
        return view;
    }
}

typedef MenuItem = {
    label:String,
    ?shortcut:String,
    ?action:() -> Void,
    ?submenu:Array<MenuItem>,
}
