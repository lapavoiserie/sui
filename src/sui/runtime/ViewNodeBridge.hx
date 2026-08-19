package sui.runtime;

import sui.View;
import sui.modifiers.ViewModifier;

/**
    Runtime view tree bridge for dynamic renderers.

    Exposes the Haxe view tree via C functions so native renderers
    (SwiftUI DynamicView, Compose DynamicComposable, etc.) can
    traverse and render it without compile-time codegen.

    Used by `mui watch` for hot reload — the native host stays running
    while the .cppia script is reloaded with new view code.

    `@:keep` — every method here is reached only from the C bridge via
    reflection, so DCE would otherwise strip the class in a dynamic-render
    build whose Haxe never references it directly.

    **The walk itself is not here.** It lives in `sui.nui.ViewSource`, sui's
    implementation of [nui's pull contract](https://lapavoiserie.github.io/nui/#/pull-mode),
    and these accessors forward to it. They stay because C reaches them by
    symbol and an interface has no static entry points — but a second copy of
    "how do I read a sui view" is exactly the kind of duplicate that drifts
    without ever crashing.
**/
@:keep
class ViewNodeBridge {
    /** Current app instance. **/
    static var _app:Dynamic = null;

    /** Every mounted root: the Primary ("body") first, then whatever surface
        roots the mui layer registered. Rebuilt together — see `rebuild`. **/
    static var _roots:Array<SurfaceRoot> = [];

    /**
        The mui layer's hook for declaring extra roots.

        This class is sui core and may not import `mui` — the surface
        vocabulary lives there. `sui.mui.App` installs a provider that reads
        the app's declarations and answers the roots sui hosts (today: one
        Preferences root, for the macOS Settings scene). A plain `sui.App`
        installs nothing and keeps exactly one root.
    **/
    public static var extraRootsOf:Dynamic -> Array<{id:String, content:() -> View}> = null;

    /** Every declared command set, sampled with the roots — see `rebuild`. **/
    static var _commandSets:Array<CommandSetRecord> = [];

    /**
        The mui layer's hook for declaring command sets — same layering as
        `extraRootsOf`: the bridge is sui core and may not import `mui`, so
        `sui.mui.App` installs a provider that maps the app's CommandSet
        declarations into the structural `CommandEntry` shape. The generated
        macOS menu bar (`DynamicAppCommands`) enumerates the result through
        the C entry points below.
    **/
    public static var commandSetsOf:Dynamic -> Array<{id:String, commands:() -> Array<CommandEntry>}> = null;

    /**
        sui's view of itself through the shared node model — the Primary's.

        Exposed so a consumer that knows nothing about sui — a devtool, an
        inspector, a remote protocol, another renderer — can walk the tree
        through `nui` rather than through these C entry points.
    **/
    public static function source():sui.nui.ViewSource {
        return _roots.length > 0 ? _roots[0].source : null;
    }

    /** Set the app instance, discover its roots and command sets, and build. **/
    public static function setApp(app:Dynamic):Void {
        _app = app;
        _roots = [new SurfaceRoot("body", function() return _app.body())];
        if (extraRootsOf != null) {
            for (extra in extraRootsOf(app))
                _roots.push(new SurfaceRoot(extra.id, extra.content));
        }
        _commandSets = [];
        if (commandSetsOf != null) {
            for (set in commandSetsOf(app))
                _commandSets.push(new CommandSetRecord(set.id, set.commands));
        }
        rebuild();
    }

    /**
        Rebuild every root — always every root, and that is structural, not
        laziness: the roots share the app's one `rui.Lifetime`, so the pass
        opens once before the first root and closes once after the last. A
        partial rebuild would close the pass without the skipped roots having
        re-declared their `keep` keys, and the sweep would release resources
        those roots still hold. (qui's cover escapes this by owning its own
        Lifetime inside its host; sui's roots are all driven from the app.)
    **/
    public static function rebuild():Void {
        if (_app == null) return;
        // Reset first: a body can throw, and a scope left open would
        // attribute the next generation's reads to the failed one.
        sui.runtime.ReadScope.reset();
        _app.lifetime.beginPass();
        for (root in _roots) {
            // Each root's shape-deciding reads are recorded separately. After
            // LiveProps has moved every displayed value into a thunk, what is
            // left reading here is exactly what decides this root's shape.
            sui.runtime.ReadScope.begin();
            root.view = root.content();
            root.structural = sui.runtime.ReadScope.end();
            root.source = new sui.nui.ViewSource(root.view);
            // Force the lazy parts, so a write arriving before the first frame
            // is classified against a complete picture rather than an empty one.
            root.source.classify();
        }
        // Command sets sample inside the same pass, for the same reason the
        // roots rebuild together: a `keep` declared while building a menu is
        // swept like any other if its pass closes without it. What a set's
        // thunk reads decides the menu's *content*, so those reads are
        // structural — recorded per set and consulted by `isStructural`.
        for (set in _commandSets) {
            sui.runtime.ReadScope.begin();
            set.current = set.commands();
            set.structural = sui.runtime.ReadScope.end();
            if (set.current == null) set.current = [];
        }
        // After the last classify, not after each body(): that is where the
        // lazy parts were forced, so it is where declaring has finished.
        _app.lifetime.endPass();
    }

    /**
        Whether a write to this cell changes some tree's *shape*.

        The renderer asks before deciding what to do with a write: a structural
        one rebuilds, a value one tells the views that display it to ask again.
        The answer spans every root — the roots rebuild together (see
        `rebuild`), so "structural anywhere" is the honest unit. Unknown
        answers "yes" — a name nobody has read yet is one this generation has
        not reached, and rebuilding is the answer that cannot be wrong.
    **/
    public static function isStructural(name:String):Bool {
        if (name == null || name == "") return true;
        if (_roots.length == 0) return true;
        var displayed = false;
        for (root in _roots) {
            for (known in root.structural) if (known == name) return true;
            if (root.source == null) return true;
            for (known in root.source.structuralNames()) if (known == name) return true;
            if (!displayed)
                for (known in root.source.valueNames()) if (known == name) { displayed = true; break; }
        }
        // A cell read while sampling a command set shapes the menu the same
        // way a body read shapes a tree.
        for (set in _commandSets)
            for (known in set.structural) if (known == name) return true;
        // Displayed somewhere, and read nowhere that shapes a tree: a value
        // write, which is the only case worth the narrow path. Read nowhere
        // at all: rebuilding is the answer that cannot be wrong, and a cell
        // nothing displays is not one anybody writes in a loop.
        return !displayed;
    }

    // --- Command sets (the menu bar's data, called from C) ---
    //
    // Enumeration by index, strings out, an int-indexed invoke back in — the
    // same closure-never-crosses rule as everything else on this bridge. The
    // arrays behind the indices are this generation's samples; a menu held
    // open across a rebuild may name an index the new sample no longer has,
    // so every accessor bounds-guards and an out-of-range invoke is a no-op.

    public static function commandSetCount():Int {
        return _commandSets.length;
    }

    public static function commandSetId(set:Int):String {
        if (set < 0 || set >= _commandSets.length) return "";
        return _commandSets[set].id;
    }

    public static function commandCount(set:Int):Int {
        if (set < 0 || set >= _commandSets.length) return 0;
        return _commandSets[set].current.length;
    }

    public static function commandLabel(set:Int, index:Int):String {
        var entry = commandAt(set, index);
        return entry == null ? "" : entry.label;
    }

    /** "" when the command has no shortcut. **/
    public static function commandShortcut(set:Int, index:Int):String {
        var entry = commandAt(set, index);
        return entry == null || entry.shortcut == null ? "" : entry.shortcut;
    }

    public static function invokeCommand(set:Int, index:Int):Void {
        var entry = commandAt(set, index);
        if (entry != null) entry.action();
    }

    static function commandAt(set:Int, index:Int):Null<CommandEntry> {
        if (set < 0 || set >= _commandSets.length) return null;
        var current = _commandSets[set].current;
        if (index < 0 || index >= current.length) return null;
        return current[index];
    }

    /** Optional per-frame delegate: pumps an external source (e.g. a WebSocket
        queue) on the main thread and reports whether the tree should rebuild. **/
    static var _poll:Void->Bool = null;

    /** Register the poll delegate (called by a dynamic app that streams its UI
        from a live source rather than a fixed body()). **/
    public static function setPoll(f:Void->Bool):Void {
        _poll = f;
    }

    /** Pump the poll delegate and rebuild if it reports a change. Returns true
        when the tree changed, so the native host can trigger a re-render. **/
    public static function poll():Bool {
        pumpHaxeEvents();
        if (_poll == null) return false;
        var changed = _poll();
        if (changed) rebuild();
        return changed;
    }

    static var _pumpBroken = false;

    /** Let Haxe's own scheduled work run. Without this a `haxe.Timer` an
        application creates never fires — silently. The entry point pumps the
        loop after `main()` returns, and under sui the Haxe `main` never runs at
        all: Swift boots the runtime and asks for the tree. The host's 100ms
        poll timer is the one periodic visit Haxe gets, so the pump lives here.
        On a threaded target — every hxcpp build — the timer registers with the
        current thread's event loop, not `haxe.MainLoop`. **/
    static function pumpHaxeEvents():Void {
        if (_pumpBroken) return;
        try {
            #if (target.threaded && !cppia)
            sys.thread.Thread.current().events.progress();
            #elseif !js
            @:privateAccess haxe.MainLoop.tick();
            #end
        } catch (e:Dynamic) {
            _pumpBroken = true;
            trace("[sui] no Haxe event loop on this thread; haxe.Timer will not fire: " + e);
        }
    }

    /** Optional sink for input edits: a native control (TextField, Toggle…)
        writes a value at a data-model path back into the app. **/
    static var _dataSink:(String, String) -> Void = null;

    public static function setDataSink(f:(String, String) -> Void):Void {
        _dataSink = f;
    }

    /** Called from the C bridge when a native input changes. **/
    public static function setData(path:String, value:String):Void {
        if (_dataSink != null) _dataSink(path, value);
    }

    /** The theme accent (e.g. a surface's primaryColor, hex) that the native
        host tints controls with. "" means use the platform default. **/
    static var _accent:String = "";

    public static function setAccent(hex:String):Void {
        _accent = hex != null ? hex : "";
    }

    public static function getAccent():String {
        return _accent;
    }

    /** Optional sink for renderer-originated actions carrying an extra context
        as JSON (e.g. a Board drop's {card, lane, index}). **/
    static var _actionSink:(String, String) -> Void = null;

    public static function setActionSink(f:(String, String) -> Void):Void {
        _actionSink = f;
    }

    /** Called from the C bridge when the renderer fires an action (name + a JSON
        extra-context object). **/
    public static function fireAction(name:String, extraJson:String):Void {
        if (_actionSink != null) _actionSink(name, extraJson);
    }

    /** Get the Primary root's view node. Returns an opaque pointer. **/
    public static function getRoot():View {
        return _roots.length > 0 ? _roots[0].view : null;
    }

    /** Get a declared surface root's view node by its stable id ("body" is
        the Primary). Null when no such root is mounted — the Swift side draws
        nothing, which is the degradation contract. **/
    public static function getRootFor(id:String):View {
        for (root in _roots) if (root.id == id) return root.view;
        return null;
    }

    // --- View node accessors (called from C bridge) ---
    //
    // All of them forward to `sui.nui.ViewSource`. C may ask before `setApp`
    // has run, so a source always exists: its accessors already answer "" / 0
    // / false for a null node, which is what these returned before.
    //
    // The few that still read a field directly -- text, a button's label --
    // resolve the node through the source first. A walker holds the node it was
    // handed, not the one it expands to, so asking a ConditionalView for its
    // text has to reach the branch: reading the raw node returned "" and drew
    // an empty label with nothing to say why.

    /** A source that always exists — the Primary's, or an empty one before
        setApp. The node accessors are root-agnostic (they take the node they
        are asked about), so any live source serves every root's nodes. **/
    static var _orphan:sui.nui.ViewSource = null;

    static function reader():sui.nui.ViewSource {
        var primary = source();
        if (primary != null) return primary;
        if (_orphan == null) _orphan = new sui.nui.ViewSource(null);
        return _orphan;
    }


    /** Get the viewType string (e.g., "VStack", "Text", "Button"). **/
    public static function getViewType(node:View):String {
        return reader().typeOf(node);
    }

    /** Get the number of children. **/
    public static function getChildCount(node:View):Int {
        return reader().childCount(node);
    }

    /** Get a child by index. **/
    public static function getChild(node:View, index:Int):View {
        return reader().childAt(node, index);
    }

    /** Get a string property (e.g., "label", "content", "placeholder"). **/
    public static function getStringProperty(node:View, key:String):String {
        return reader().stringProp(node, key);
    }

    /** Get an int property. **/
    public static function getIntProperty(node:View, key:String):Int {
        return reader().intProp(node, key);
    }

    /** Get a float property. **/
    public static function getFloatProperty(node:View, key:String):Float {
        return reader().floatProp(node, key);
    }

    /** Get a bool property. **/
    public static function getBoolProperty(node:View, key:String):Bool {
        return reader().boolProp(node, key);
    }

    /** Check if a property exists. **/
    public static function hasProperty(node:View, key:String):Bool {
        return reader().hasProp(node, key);
    }

    /** Get the number of modifiers. **/
    public static function getModifierCount(node:View):Int {
        return reader().modifierCount(node);
    }

    /** Get modifier type name at index. **/
    public static function getModifierType(node:View, index:Int):String {
        return reader().modifierType(node, index);
    }

    /** Get modifier float parameter (e.g., padding value, opacity). **/
    public static function getModifierFloat(node:View, index:Int, paramIndex:Int):Float {
        return reader().modifierFloat(node, index, paramIndex);
    }

    /** Get modifier string parameter (e.g., color name, font style). **/
    public static function getModifierString(node:View, index:Int, paramIndex:Int):String {
        return reader().modifierString(node, index, paramIndex);
    }

    // --- Text special accessors ---

    /** Get the text content (for Text views). **/
    public static function getTextContent(node:View):String {
        node = reader().valueOf(node);
        if (node == null) return "";
        var content:Dynamic = Reflect.field(node, "content");
        return content != null ? Std.string(content) : "";
    }

    /** Get the swift expression for state-interpolated text. **/
    public static function getTextExpression(node:View):String {
        node = reader().valueOf(node);
        if (node == null) return "";
        var expr:Dynamic = Reflect.field(node, "swiftExpression");
        if (expr == null) expr = Reflect.field(node, "composeExpression");
        return expr != null ? Std.string(expr) : "";
    }

    // --- Button special accessors ---

    /** Get button label. **/
    public static function getButtonLabel(node:View):String {
        node = reader().valueOf(node);
        if (node == null) return "";
        var label:Dynamic = Reflect.field(node, "label");
        return label != null ? Std.string(label) : "";
    }

    /** Get button action ID (for invoking via bridge). **/
    public static function getButtonActionId(node:View):Int {
        return reader().actionId(node);
    }

    /** The cells a node's value depends on, joined for the C bridge. **/
    public static function getValueDependencies(node:View):String {
        return reader().valueDependencies(node).join(",");
    }

    // --- Tabs ----------------------------------------------------------------
    //
    // A TabView pushes its tab contents into `children`, but the label and icon
    // beside each one stay in `tabs`. A host drawing the bar needs them.

    public static function getTabCount(node:View):Int {
        return reader().tabCount(node);
    }

    public static function getTabTitle(node:View, index:Int):String {
        return reader().tabTitle(reader().resolveWalked(node), index);
    }

    public static function getTabIcon(node:View, index:Int):String {
        return reader().tabIcon(reader().resolveWalked(node), index);
    }

    // --- Named state, for controls whose binding is a name -------------------
    //
    // A sui control carries its binding as a String: `new TextField("Name",
    // "userName")`. The transpiler turned that into `$appState.userName`, a
    // real SwiftUI binding. The dynamic renderer has no appState, so it reads
    // and writes the cell itself, by the same name.

    /** The value of a named state, rendered as a string for the host. **/
    public static function getStateValue(name:String):String {
        var value = sui.state.State.peekByName(name);
        return value == null ? "" : Std.string(value);
    }

    /** Whether the name resolves at all — "" is a value, absence is not. **/
    public static function hasStateValue(name:String):Bool {
        return sui.state.State.existsByName(name);
    }

    /**
        A value edited by a native control, written back into the cell.

        Through `_applyFromSwift`, so the write reaches Haxe effects but is not
        pushed back to the platform it came from: echoing it would fight the
        control for the cursor, which is the loop `applyExternal` exists to
        break. The tree is rebuilt by the state observer either way, so what is
        on screen follows.
    **/
    public static function setStateValue(name:String, raw:String):Void {
        sui.state.State._applyFromSwift(name, raw);
    }

    /** Invoke a Button's action closure directly.

        The static bridge routes taps through an integer id into the Callbacks
        store because a Haxe closure captured by a Swift/ARC closure is invisible
        to the hxcpp GC. The dynamic renderer has no such problem: it holds the
        live view trees (each root record, a GC root), so the closure sitting on the node
        stays reachable. So we just call it — no id, no Callbacks indirection. **/
    public static function invokeButtonAction(node:View):Void {
        reader().invokeAction(node);
    }
}

/**
    One mounted root: a stable id, the thunk that builds it, and this
    generation's tree, reader and shape-deciding cells. The view field is a GC
    root on purpose — the native side holds only opaque pointers, and nui's
    contract is that the Haxe side keeps every root referenced.
**/
private class SurfaceRoot {
    public var id:String;
    public var content:() -> View;
    public var view:View = null;
    public var source:sui.nui.ViewSource = null;
    public var structural:Array<String> = [];

    public function new(id:String, content:() -> View) {
        this.id = id;
        this.content = content;
    }
}

/**
    One command, structurally: what `mui.surface.Command` carries, without
    naming it — the bridge is sui core and the mui layer hands these across
    as anonymous objects. The action stays a Haxe closure on this side of the
    bridge; only an index ever crosses.
**/
typedef CommandEntry = {
    var label:String;
    var shortcut:Null<String>;
    var action:() -> Void;
}

/**
    One declared command set: a stable id, the thunk that samples it, this
    generation's commands and the cells the sampling read (structural — they
    decide the menu's content).
**/
private class CommandSetRecord {
    public var id:String;
    public var commands:() -> Array<CommandEntry>;
    public var current:Array<CommandEntry> = [];
    public var structural:Array<String> = [];

    public function new(id:String, commands:() -> Array<CommandEntry>) {
        this.id = id;
        this.commands = commands;
    }
}
