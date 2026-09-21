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
#if (cpp && !cppia)
@:cppFileCode('
#include <atomic>
typedef void (*sui_pump_requester)(void);
static sui_pump_requester s_sui_pump_requester = nullptr;
static std::atomic<bool> s_sui_pump_pending{false};

// Installed by the host (viewnode_set_pump_requester), which then starts the
// watcher. The requester only posts to the main queue: it runs on the watcher.
extern "C" void sui_bridge_set_pump_requester(sui_pump_requester fn) {
    s_sui_pump_requester = fn;
}

// One request until the host has pumped: a burst of queued events is one visit.
static void sui_bridge_request_pump() {
    sui_pump_requester requester = s_sui_pump_requester;
    if (requester && !s_sui_pump_pending.exchange(true)) requester();
}
')
#end
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
        The last few generations of view trees, kept alive on purpose.

        A node crosses to the renderer as a raw `hx::Object*`, and Swift's
        `ViewNode` is a **struct holding that pointer**, captured into the
        closures SwiftUI keeps — a `Slider`'s `Binding` get and set among them.
        A rebuild allocates a fresh tree and dropped the old one on the spot, so
        those captured pointers referred to memory the collector was free to
        take back. Reading a property off one was a use-after-free.

        It was not theoretical. Dragging the slider in
        `mui/examples/kitchen-sink` killed the app repeatedly — EXC_BAD_ACCESS
        at 0x0, reported inside `getStringProperty`, which is simply the first
        thing that touches the node. A drag rebuilds per frame, so it reaches
        the window between a pointer being handed out and being used faster
        than anything else does.

        Holding the previous generations turns that into a **stale read**: the
        renderer gets the value the node had when it was built, and SwiftUI
        replaces the view with the current generation's on the next pass. For a
        control that binds by NAME -- every two-way control here -- even the
        stale read is right, because the name does not change and the write
        goes through `setStateValue`, which never looks at a node.

        Four, not one, because SwiftUI may hold a closure across more than one
        pass; and not unbounded, because that is a leak with a nicer name.
    **/
    static var _generations:Array<Array<View>> = [];

    static inline var GENERATIONS = 4;

    // ------------------------------------------------------------------
    // Handles
    //
    // A node used to cross as a raw `hx::Object*`, and Swift's `ViewNode` is a
    // struct holding it, captured into the closures SwiftUI keeps. That was a
    // crash, reproducibly: dragging the slider in `mui/examples/kitchen-sink`
    // killed the app every few seconds.
    //
    // The first reading was that the tree had been COLLECTED, and keeping the
    // last generations alive did not help. The faulting instruction said why:
    //
    //     ldr  x21, [x21]      ; the node
    //     cbz  x21, ...        ; not null
    //     ldr  x8,  [x21]      ; its class pointer
    //     ldr  x8,  [x8]       ; <-- SIGSEGV, x8 was 0
    //
    // A non-null object with a ZEROED header is one hxcpp's Immix collector
    // has **moved**. Liveness was never the problem; the address was. A
    // pointer handed across the boundary is a promise the GC does not make.
    //
    // So nothing hands out addresses. A node crosses as a small integer, and
    // the Haxe side holds what it names in a map the collector updates like
    // any other reference.
    // ------------------------------------------------------------------

    // ...and the handle names a PLACE, not a node.
    //
    // The first version mapped a handle to the node it was issued for. That
    // stopped the crash and broke the drag: a slider moved on a click and not
    // on a drag. A drag writes `level` on every frame, and this screen's text
    // reads `level` inside `body()`, so every frame rebuilds -- genuinely,
    // that read is structural. SwiftUI kept the closure it captured a few
    // generations back, its handle aged out, `bindingName` found nothing on a
    // null node, and the binding fell back to one that reads an empty value:
    // the knob went back where it started. A click is one write, so its
    // handle was still in reach.
    //
    // Which is the rule this repository already states for identity
    // (`nui`'s pull contract, `ViewNode.identity`): **the place, never the
    // pointer**. A handle records where its node was reached from -- a root,
    // or a parent handle and a child index -- and resolves against the
    // CURRENT tree. The node it was issued for is kept only as the answer
    // when that place no longer exists, so a vanished view reads stale
    // rather than empty.

    static var _nextHandle = 1;
    static var _places = new Map<Int, Place>();

    /** Bumped on every rebuild; a place resolved in this one is not walked again. **/
    static var _generation = 0;

    /** A handle for a root, by its id ("body" is the Primary). **/
    public static function handleOfRoot(id:String, node:Dynamic):Int {
        if (node == null) return 0;
        var known = _rootHandles.get(id);
        if (known != null) {
            var place = _places.get(known);
            place.node = node;
            place.signature = signatureOf(node);
            place.generation = _generation;
            return known;
        }
        var handle = issue(new Place(0, 0, id, node, _generation));
        _rootHandles.set(id, handle);
        return handle;
    }

    static var _rootHandles = new Map<String, Int>();

    /** A handle for a node's child at an index. **/
    public static function handleOfChild(parent:Int, index:Int, node:Dynamic):Int {
        if (node == null) return 0;
        var key = parent + ":" + index;
        var known = _childHandles.get(key);
        if (known != null) {
            var place = _places.get(known);
            if (place != null) {
                place.node = node;
                place.signature = signatureOf(node);
                place.generation = _generation;
                return known;
            }
        }
        var handle = issue(new Place(parent, index, null, node, _generation));
        _childHandles.set(key, handle);
        return handle;
    }

    /** One handle per place, so a place asked twice is the same handle. **/
    static var _childHandles = new Map<String, Int>();

    static function issue(place:Place):Int {
        place.signature = signatureOf(place.node);
        var handle = _nextHandle++;
        _places.set(handle, place);
        return handle;
    }

    /** The node at a handle's place in the current tree. **/
    public static function nodeOf(handle:Int):Dynamic {
        if (handle == 0) return null;
        var place = _places.get(handle);
        if (place == null) return null;
        if (place.generation == _generation) return place.node;

        var current:Dynamic = if (place.parent == 0) {
            getRootFor(place.rootId);
        } else {
            var parent = nodeOf(place.parent);
            parent == null || place.index >= getChildCount(parent)
                ? null
                : getChild(parent, place.index);
        };
        // A place that no longer exists answers what was there. Stale, not
        // empty: an empty answer is what made the knob snap back.
        if (tracing()) {
            if (current == null)
                Sys.stderr().writeString("[sui] place " + handle + " vanished (was "
                    + getViewType(place.node) + ")\n");
            else if (getViewType(current) != getViewType(place.node))
                Sys.stderr().writeString("[sui] place " + handle + " now " + getViewType(current)
                    + ", was " + getViewType(place.node) + "\n");
        }
        if (current != null) {
            place.node = current;
            place.signature = signatureOf(current);
        }
        place.generation = _generation;
        return place.node;
    }

    // ...and a place is not enough on its own, which is Benjamin's question
    // the day this shipped: what if a component is INSERTED?
    //
    // Then the place names something else. A label appears above a slider,
    // the slider moves from index 3 to index 4, and a closure SwiftUI kept
    // from before the insertion resolves index 3 to whatever sits there now.
    // Reading a stale label is harmless. WRITING is not: an old slider's
    // `set` would resolve to, say, a toggle, find `isOnBinding` on it, and
    // put "0.37" into a Bool cell. A wrong write into the wrong cell, in the
    // window between the rebuild and SwiftUI re-running the bodies that
    // replace those closures -- narrow, and exactly where a drag that makes
    // a warning appear lives.
    //
    // So a handle also carries a SIGNATURE of the node it was issued for:
    // its type and the cell it edits. `nodeOfChecked` answers null when the
    // place now holds something with a different one, and a null node is
    // inert everywhere -- no name, so no write. A dropped write in a stale
    // closure, never a wrong one. Two controls of the same type editing the
    // SAME cell are interchangeable for this purpose, which is the point:
    // for a control, identity is the cell.
    //
    // What this does not give is identity for rows that MOVE. That is what a
    // key is for (`nodeId`, nui's sibling keys), and sui's own trees carry
    // none yet.

    static final BINDINGS = ["textBinding", "isOnBinding", "valueBinding", "selectionBinding", "isoStateName"];

    /** Sixteen bits of what a node IS: its type and the cell it edits. **/
    static function signatureOf(node:Dynamic):Int {
        if (node == null) return 0;
        var text = getViewType(node);
        for (key in BINDINGS) {
            var name = getStringProperty(node, key);
            if (name != null && name != "") { text += "|" + name; break; }
        }
        var hash = 5381;
        for (i in 0...text.length) hash = ((hash * 33) ^ text.charCodeAt(i)) & 0xffff;
        return hash;
    }

    /** The signature a handle for this place must carry. **/
    public static function signatureOfPlace(handle:Int):Int {
        nodeOf(handle);
        var place = _places.get(handle);
        return place == null ? 0 : place.signature;
    }

    /** The node at a place, if it is still what the handle was issued for. **/
    public static function nodeOfChecked(handle:Int, signature:Int):Dynamic {
        var node = nodeOf(handle);
        if (node == null) return null;
        return _places.get(handle).signature == signature ? node : null;
    }

    /** A new generation: every place resolves afresh on its next read. **/
    static function turnHandles():Void {
        _generation++;
    }

    /**
        The current generation, which the C bridge folds into every handle it
        hands out.

        A handle naming only its place was too stable. `DynamicView` holds
        nothing but its `ViewNode`, SwiftUI compares a view by its stored
        values, and a `ViewNode` whose handle had not changed compared EQUAL
        after a rebuild -- so SwiftUI skipped `body` and never read the new
        values. The text under the slider stopped following it. The renderer
        had been relying on every rebuild changing every address.

        So a handle carries both: the place in its low 32 bits, which is what
        `nodeOf` resolves, and the generation above them, which is what makes a
        rebuilt view a different value. Identity for diffing is not affected --
        `ViewNode.identity(at:)` is positional and never looked at the pointer.
    **/
    public static function generation():Int {
        return _generation;
    }

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
    /** How many times the tree has been rebuilt, for `SUI_BRIDGE_TRACE`. **/
    static var _rebuilds = 0;

    public static function rebuild():Void {
        if (_foreign != null) _foreign.rebuild();
        if (_app == null) return;
        // A drag that rebuilds per frame is the difference between a slider
        // that follows the mouse and one that lags behind it. Counted rather
        // than guessed: a value write is supposed to reach the views that
        // display the cell and rebuild nothing (see `isStructural`).
        _rebuilds++;
        if (tracing())
            Sys.stderr().writeString("[sui] rebuild #" + _rebuilds + "\n");
        // Reset first: a body can throw, and a scope left open would
        // attribute the next generation's reads to the failed one.
        sui.runtime.ReadScope.reset();
        // The generation about to be replaced, held so the pointers already
        // handed to the renderer stay readable. See `_generations`.
        var previous:Array<View> = [];
        for (root in _roots) if (root.view != null) previous.push(root.view);
        if (previous.length > 0) {
            _generations.push(previous);
            while (_generations.length > GENERATIONS) _generations.shift();
        }
        turnHandles();
        _app.lifetime.beginPass();
        for (root in _roots) {
            // Each root's shape-deciding reads are recorded separately. After
            // LiveProps has moved every displayed value into a thunk, what is
            // left reading here is exactly what decides this root's shape.
            sui.runtime.ReadScope.begin();
            root.view = root.content();
            root.structural = sui.runtime.ReadScope.end();
            // What this root's SHAPE depends on. A cell listed here rebuilds
            // the tree when written; one that is only displayed should not be.
            if (tracing() && _rebuilds == 1)
                Sys.stderr().writeString("[sui] " + root.id + " shape reads: ["
                    + root.structural.join(", ") + "]\n");
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
        // A received tree displays none of this application's cells, so the
        // narrow path has nothing to update: a write is how the application
        // says a tree arrived (see `readThrough`).
        if (_foreign != null) return true;
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
        // Cleared before pumping: an event queued while the pump runs asks
        // for the next visit instead of being folded into this one.
        #if (cpp && !cppia)
        untyped __cpp__("s_sui_pump_pending = false");
        #end
        pumpHaxeEvents();
        if (_poll == null) return false;
        var changed = _poll();
        if (changed) rebuild();
        return changed;
    }

    static var _pumpBroken = false;

    static var _watching = false;

    /**
        Ask the host for a visit whenever work is queued for the main thread,
        from any thread.

        The 100 ms poll alone meant a frame arriving off a socket waited for
        the next tick before anything drew it: `dui.socket.Pump` and
        `cafos.client.Marshal` queue onto this thread's `sys.thread.EventLoop`,
        and nothing looked at it in between. A level meter fed that way showed
        ten values a second whatever the sender sent — the defect `wui` had,
        measured by the Farceur session at 60 trees a second shown as ten.

        The loop's `wait()` returns each time something is queued (`run`,
        `repeat` and `runPromised` each release it), so one thread waits there
        and asks the host each time. It consumes wake-ups nobody else uses: the
        main thread only ever calls `progress()`.

        Called on the main thread by `viewnode_set_pump_requester`, once the
        host has installed its requester. The poll stays, for timers that come
        due without anything being queued.
    **/
    public static function watchMainEvents():Void {
        if (_watching) return;
        #if (cpp && !cppia)
        var events:Null<sys.thread.EventLoop> = try sys.thread.Thread.current().events catch (_:Dynamic) null;
        if (events == null) return;
        _watching = true;
        final loop:sys.thread.EventLoop = events;
        sys.thread.Thread.create(() -> {
            while (true) {
                loop.wait();
                untyped __cpp__("sui_bridge_request_pump()");
            }
        });
        #end
    }

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
        // An edit on a received control runs the action it carries.
        if (_foreign != null && sui.nui.Received.edit(_foreign, path, value)) return;
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
    public static function getRoot():Dynamic {
        if (_foreign != null) return _foreign.root();
        return _roots.length > 0 ? _roots[0].view : null;
    }

    /** Get a declared surface root's view node by its stable id ("body" is
        the Primary). Null when no such root is mounted — the Swift side draws
        nothing, which is the degradation contract. **/
    public static function getRootFor(id:String):Dynamic {
        if (_foreign != null && id == "body") return _foreign.root();
        for (root in _roots) if (root.id == id) return root.view;
        return null;
    }

    // --- A tree that arrived ---------------------------------------------------

    static var _foreign:Null<nui.SelfSource> = null;

    /**
        Draw a tree this application did not build, in place of `body()`.

        ```haxe
        var tree:Null<nui.Node> = null;
        sui.runtime.ViewNodeBridge.readThrough(new nui.SelfSource(() -> {
            generation; // a cell, read here -- see below
            return tree != null ? tree : waiting();
        }));
        reception.onTree = (t, _) -> { tree = t; generation++; };
        ```

        The same call `aui` has, and the same shape of application: a panel
        written once draws a received tree on either. The tree is read directly
        (`sui.nui.Received` answers the renderer's questions in canonical terms),
        so an edit made on a received control runs the action it carries, and
        goes home.

        **Something must say a new tree arrived.** Writing a cell does: this
        bridge rebuilds on any write to a cell no view displays, and the rebuild
        re-evaluates the source's thunk. Only the Primary root is replaced; a
        Preferences root the application declared stays its own.

        Pass `null` to hand the screen back to `body()`.
    **/
    public static function readThrough(source:Null<nui.SelfSource>):Void {
        _foreign = source;
    }

    /** Whether a received tree is drawing. **/
    public static function reading():Bool {
        return _foreign != null;
    }

    /** The node as a received one, or null when it is one of this app's views --
        a Preferences root keeps drawing its own while a tree is received. **/
    static function received(node:Dynamic):Null<nui.Node> {
        return _foreign != null && Std.isOfType(node, nui.Node) ? (node : nui.Node) : null;
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
    public static function getViewType(node:Dynamic):String {
        var r = received(node);
        if (r != null) return sui.nui.Received.typeOf(_foreign, r);
        return reader().typeOf(node);
    }

    /** Get the number of children. **/
    public static function getChildCount(node:Dynamic):Int {
        var r = received(node);
        if (r != null) return _foreign.childCount(r);
        return reader().childCount(node);
    }

    /** Get a child by index. **/
    public static function getChild(node:Dynamic, index:Int):Dynamic {
        var r = received(node);
        if (r != null) return _foreign.childAt(r, index);
        return reader().childAt(node, index);
    }

    /** Get a string property (e.g., "label", "content", "placeholder"). **/
    public static function getStringProperty(node:Dynamic, key:String):String {
        var r = received(node);
        if (r != null) return sui.nui.Received.stringProp(_foreign, r, key);
        return reader().stringProp(node, key);
    }

    /** Get an int property. **/
    public static function getIntProperty(node:Dynamic, key:String):Int {
        var r = received(node);
        if (r != null) return _foreign.intProp(r, key);
        return reader().intProp(node, key);
    }

    /** Get a float property. **/
    public static function getFloatProperty(node:Dynamic, key:String):Float {
        var r = received(node);
        if (r != null) return _foreign.floatProp(r, key);
        return reader().floatProp(node, key);
    }

    /** Get a bool property. **/
    public static function getBoolProperty(node:Dynamic, key:String):Bool {
        var r = received(node);
        if (r != null) return _foreign.boolProp(r, key);
        return reader().boolProp(node, key);
    }

    /** Check if a property exists. **/
    public static function hasProperty(node:Dynamic, key:String):Bool {
        var r = received(node);
        if (r != null) return _foreign.hasProp(r, key);
        return reader().hasProp(node, key);
    }

    /** Get the number of modifiers. **/
    public static function getModifierCount(node:Dynamic):Int {
        var r = received(node);
        if (r != null) return _foreign.modifierCount(r);
        return reader().modifierCount(node);
    }

    /** Get modifier type name at index. **/
    public static function getModifierType(node:Dynamic, index:Int):String {
        var r = received(node);
        if (r != null) return sui.nui.Received.modifierType(_foreign, r, index);
        return reader().modifierType(node, index);
    }

    /** Get modifier float parameter (e.g., padding value, opacity). **/
    public static function getModifierFloat(node:Dynamic, index:Int, paramIndex:Int):Float {
        var r = received(node);
        if (r != null) return _foreign.modifierFloat(r, index, paramIndex);
        return reader().modifierFloat(node, index, paramIndex);
    }

    /** Get modifier string parameter (e.g., color name, font style). **/
    public static function getModifierString(node:Dynamic, index:Int, paramIndex:Int):String {
        var r = received(node);
        if (r != null) return _foreign.modifierString(r, index, paramIndex);
        return reader().modifierString(node, index, paramIndex);
    }

    // --- Text special accessors ---

    /** Get the text content (for Text views). **/
    public static function getTextContent(node:Dynamic):String {
        var r = received(node);
        if (r != null) return sui.nui.Received.stringProp(_foreign, r, "text");
        node = reader().valueOf(node);
        if (node == null) return "";
        var content:Dynamic = Reflect.field(node, "content");
        return content != null ? Std.string(content) : "";
    }

    /** Get the swift expression for state-interpolated text. **/
    public static function getTextExpression(node:Dynamic):String {
        if (received(node) != null) return "";
        node = reader().valueOf(node);
        if (node == null) return "";
        var expr:Dynamic = Reflect.field(node, "swiftExpression");
        if (expr == null) expr = Reflect.field(node, "composeExpression");
        return expr != null ? Std.string(expr) : "";
    }

    // --- Button special accessors ---

    /** Get button label. **/
    public static function getButtonLabel(node:Dynamic):String {
        var r = received(node);
        if (r != null) return sui.nui.Received.stringProp(_foreign, r, "label");
        node = reader().valueOf(node);
        if (node == null) return "";
        var label:Dynamic = Reflect.field(node, "label");
        return label != null ? Std.string(label) : "";
    }

    /** Get button action ID (for invoking via bridge). **/
    public static function getButtonActionId(node:Dynamic):Int {
        var r = received(node);
        if (r != null) return _foreign.actionId(r);
        return reader().actionId(node);
    }

    /** The cells a node's value depends on, joined for the C bridge. **/
    public static function getValueDependencies(node:Dynamic):String {
        // A received tree displays no cell of this application.
        if (received(node) != null) return "";
        return reader().valueDependencies(node).join(",");
    }

    // --- Tabs ----------------------------------------------------------------
    //
    // A TabView pushes its tab contents into `children`, but the label and icon
    // beside each one stay in `tabs`. A host drawing the bar needs them.

    public static function getTabCount(node:Dynamic):Int {
        if (received(node) != null) return 0;
        return reader().tabCount(node);
    }

    public static function getTabTitle(node:Dynamic, index:Int):String {
        if (received(node) != null) return "";
        return reader().tabTitle(reader().resolveWalked(node), index);
    }

    public static function getTabIcon(node:Dynamic, index:Int):String {
        if (received(node) != null) return "";
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
        // What arrived AND what the cell holds afterwards: the two differ when
        // the value was parsed into the wrong type, which is how a slider
        // dragged through zero froze its cell there.
        if (tracing()) Sys.stderr().writeString("[sui] write " + name + " = " + raw
            + " -> " + Std.string(sui.state.State.peekByName(name)) + "\n");
    }

    static var _tracing:Null<Bool> = null;

    /** `SUI_BRIDGE_TRACE`, read once. **/
    static function tracing():Bool {
        if (_tracing == null) _tracing = Sys.getEnv("SUI_BRIDGE_TRACE") != null;
        return _tracing;
    }

    /** Invoke a Button's action closure directly.

        The static bridge routes taps through an integer id into the Callbacks
        store because a Haxe closure captured by a Swift/ARC closure is invisible
        to the hxcpp GC. The dynamic renderer has no such problem: it holds the
        live view trees (each root record, a GC root), so the closure sitting on the node
        stays reachable. So we just call it — no id, no Callbacks indirection. **/
    public static function invokeButtonAction(node:Dynamic):Void {
        var r = received(node);
        if (r != null) {
            _foreign.invokeAction(r);
            return;
        }
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

/** Where a handle's node was reached from. See `ViewNodeBridge.nodeOf`. **/
private class Place {
    public var parent:Int;
    public var index:Int;
    public var rootId:Null<String>;
    public var node:Dynamic;
    public var signature:Int = 0;
    public var generation:Int;

    public function new(parent:Int, index:Int, rootId:Null<String>, node:Dynamic, generation:Int) {
        this.parent = parent;
        this.index = index;
        this.rootId = rootId;
        this.node = node;
        this.generation = generation;
    }
}
