package sui.mui;


/**
	`sui`'s conformance for `mui.App`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
@:autoBuild(mui.macros.Surfaces.build())
class App extends sui.App {
    public function new() {
        super();
        // The bridge is sui core and may not import mui, so the mui layer
        // installs the hook that turns declarations into extra roots. Every
        // mui app sets the same static — idempotent by construction.
        sui.runtime.ViewNodeBridge.extraRootsOf = muiRoots;
    }

    /** Set the application title. Maps to sui's appName. **/
    public var appTitle(get, set):String;

    function get_appTitle():String return appName;
    function set_appTitle(v:String):String { appName = v; return v; }

    /**
        The declared roots sui hosts today: one Preferences tree, rendered by
        the generated macOS `Settings` scene (`DynamicSurfaceView` reads it by
        id). One-cardinality rule: the role's default id ("preferences") wins,
        else the first declaration. Every other role degrades to nothing here
        for now — Commands (the menu bar) is the next slice.
    **/
    static function muiRoots(app:Dynamic):Array<{id:String, content:() -> sui.View}> {
        var mine:App = cast app;
        var picked:Null<mui.surface.SurfaceDecl> = null;
        for (d in mine.surfaces()) switch (d) {
            case Tree(mui.surface.SurfaceRole.Preferences, id, _):
                if (id == "preferences") picked = d;
                if (picked == null) picked = d;
            case _:
        }
        // Guard before the switch: matching a null enum segfaults under hxcpp
        // (the lesson nui.PropValueTools already carries).
        if (picked == null) return [];
        return switch (picked) {
            case Tree(_, id, content): [{id: id, content: content}];
            case _: [];
        };
    }

    /**
        Every surface this application declares: Primary — `body()`, always —
        plus whatever `@:surface` methods collected into `declaredSurfaces()`.
        Override to declare past the sugar: `super.surfaces().concat([…])`.
    **/
    public function surfaces():Array<mui.surface.SurfaceDecl> {
        return [mui.surface.SurfaceDecl.Tree(mui.surface.SurfaceRole.Primary, "body", () -> body())]
            .concat(declaredSurfaces());
    }

    /** What `@:surface` declared. `mui.macros.Surfaces` overrides this on the
        application; the default is the empty answer. **/
    public function declaredSurfaces():Array<mui.surface.SurfaceDecl> return [];
}
