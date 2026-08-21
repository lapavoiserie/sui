package sui.mui;


/**
	`sui`'s conformance for `mui.App`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
// The roles this backend can honour, stated where a macro can read them.
//
// `mui.macros.Surfaces` refuses a declaration whose role is missing from this
// list, naming this backend — degradation the application accepts on purpose
// (`@:surface(Role, optional)`) rather than degradation it never hears about.
// Widen this the day a host lands, never to quiet a build.
//
// Companion is a statement of capability, not of appetite: it says this
// backend installs a describer and *could* serve one. The networked corner
// stays off until the build asks for it with -D mui_cafos.
//
// Preferences is the Settings scene (⌘,), Auxiliary the extra windows,
// Commands the menu bar; Companion rides the describer installed below.
// Glance waits for WidgetKit.
@:hostedRoles(Preferences, Auxiliary, Commands, Companion)
@:autoBuild(mui.macros.Surfaces.build())
class App extends sui.App {
    public function new() {
        super();
        // The bridge is sui core and may not import mui, so the mui layer
        // installs the hooks that turn declarations into extra roots and
        // command sets. Every mui app sets the same statics — idempotent by
        // construction.
        sui.runtime.ViewNodeBridge.extraRootsOf = muiRoots;
        sui.runtime.ViewNodeBridge.commandSetsOf = muiCommandSets;
        // The View->Node describer, for the detached corner (Companion
        // projection now, widget snapshots in P4a): signing the shared
        // register is what lets a macOS app serve a surface to another
        // machine.
        mui.surface.Describe.impl = v -> sui.nui.Describe.describe(v);
    }

    /** Set the application title. Maps to sui's appName. **/
    public var appTitle(get, set):String;

    function get_appTitle():String return appName;
    function set_appTitle(v:String):String { appName = v; return v; }

    /**
        The declared roots sui hosts: ONE Preferences tree — the macOS
        `Settings` scene; the role's default id ("preferences") wins, else the
        first declaration — and EVERY Auxiliary tree, in declaration order,
        each rendered by a generated macOS window scene (cardinality Many:
        macOS puts N windows on one process as naturally as WinUI does).

        Every other role degrades to nothing here on purpose: Glance is the
        snapshot corner (P4a) and never becomes a live root on sui — a
        declaration must not mount just because a mapper was careless.
    **/
    static function muiRoots(app:Dynamic):Array<{id:String, content:() -> sui.View}> {
        var mine:App = cast app;
        var out:Array<{id:String, content:() -> sui.View}> = [];
        var prefs:Null<mui.surface.SurfaceDecl> = null;
        for (d in mine.surfaces()) switch (d) {
            case Tree(mui.surface.SurfaceRole.Preferences, id, _):
                if (id == "preferences") prefs = d;
                if (prefs == null) prefs = d;
            case Tree(mui.surface.SurfaceRole.Auxiliary, id, content):
                out.push({id: id, content: content});
            case _:
        }
        // Guard before the switch: matching a null enum segfaults under hxcpp
        // (the lesson nui.PropValueTools already carries). Preferences goes
        // first so the root order matches the scene order in App.swift.
        if (prefs != null) switch (prefs) {
            case Tree(_, id, content): out.unshift({id: id, content: content});
            case _:
        }
        return out;
    }

    /**
        The declared command sets, for the generated menu bar
        (`DynamicAppCommands` enumerates them through the bridge). Cardinality
        Many is natural here — every CommandSet declaration is served, in
        declaration order. The mapping into the bridge's structural
        `CommandEntry` is an explicit copy, not a cast: `mui.surface.Command`
        has final fields, and building anonymous objects sidesteps the
        class-to-structure unification question entirely.
    **/
    static function muiCommandSets(app:Dynamic):Array<{id:String, commands:() -> Array<sui.runtime.ViewNodeBridge.CommandEntry>}> {
        var mine:App = cast app;
        var sets = [];
        for (d in mine.surfaces()) switch (d) {
            case CommandSet(id, commands):
                sets.push({
                    id: id,
                    commands: function() {
                        return [for (c in commands()) ({label: c.label, shortcut: c.shortcut, action: c.action} : sui.runtime.ViewNodeBridge.CommandEntry)];
                    },
                });
            case _:
        }
        return sets;
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
