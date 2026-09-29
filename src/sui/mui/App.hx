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
// Commands the menu bar, Glance a WidgetKit widget — sampled, since the
// widget is a separate binary the application cannot reach into; Companion
// rides the describer installed below.
@:hostedRoles(Preferences, Auxiliary, Commands, Glance, Companion)
@:autoBuild(mui.macros.Surfaces.build())
@:autoBuild(mui.macros.Intents.build())
class App extends sui.App {
    public function new() {
        super();
        // The durable store, before anything durable exists. This runs inside
        // `super()` from the application's point of view, so its
        // `@:state(durable)` cells are constructed after the store is there and
        // are born from it rather than corrected afterwards.
        //
        // A macro: it expands to nothing where this platform has no store
        // implementation, so a build that asked for no durable cell does not
        // fail for a capability it never used. An application that *does* ask is
        // refused at the field, by name.
        mui.state.Durable.install();
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
        // Remembered, not sampled: the declaration's thunk would read cells the
        // subclass has not initialised yet. The surface starts following after
        // `setApp`, when the instance is whole.
        sui.mui.GlanceBridge.attach(this);

        // The first picture is NOT taken here: this constructor runs
        // before the subclass has initialised its @:state fields, so the
        // declaration's thunk would read a null cell and take the whole boot
        // down with it. The host publishes when the application leaves the
        // foreground, and whenever the application asks.
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
        var declared = mine.surfaces();
        var out:Array<{id:String, content:() -> sui.View}> = [];
        // Preferences first, so the root order matches the scene order in
        // App.swift. `pickOne` is the shared cardinality-One rule — the
        // role's default id if declared, else the first — and it also
        // retires the hxcpp trap this used to carry: it never matches a null
        // enum, which segfaults (the lesson nui.PropValueTools carries).
        var prefs = mui.surface.SurfaceDecl.SurfaceDeclTools.pickOne(declared,
            mui.surface.SurfaceRole.Preferences, "preferences");
        if (prefs != null) out.push({id: prefs.id, content: prefs.content});
        for (window in mui.surface.SurfaceDecl.SurfaceDeclTools.treesOf(declared,
                mui.surface.SurfaceRole.Auxiliary))
            out.push({id: window.id, content: window.content});
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

    /** What `@:intent` declared. `mui.macros.Intents` overrides this on the
        application; the default is the empty answer. `dui.state.Share.join`
        hands it to the registry, so a call arriving by name can run. **/
    public function declaredIntents():Array<rui.state.Shared.IntentDecl> return [];
}
