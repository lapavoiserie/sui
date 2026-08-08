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
    /** The root view tree, rebuilt on each reload. **/
    static var _root:View = null;

    /** Current app instance. **/
    static var _app:Dynamic = null;

    /** The tree reader, rebuilt with the root it describes. **/
    static var _source:sui.nui.ViewSource = null;

    /**
        sui's view of itself through the shared node model.

        Exposed so a consumer that knows nothing about sui — a devtool, an
        inspector, a remote protocol, another renderer — can walk the tree
        through `nui` rather than through these C entry points.
    **/
    public static function source():sui.nui.ViewSource {
        return _source;
    }

    /** Set the app instance and build the initial view tree. **/
    public static function setApp(app:Dynamic):Void {
        _app = app;
        rebuild();
    }

    /** Rebuild the view tree by calling body() on the app. **/
    public static function rebuild():Void {
        if (_app != null) {
            _root = _app.body();
            _source = new sui.nui.ViewSource(_root);
        }
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
        if (_poll == null) return false;
        var changed = _poll();
        if (changed) rebuild();
        return changed;
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

    /** Get the root view node. Returns an opaque pointer. **/
    public static function getRoot():View {
        return _root;
    }

    // --- View node accessors (called from C bridge) ---
    //
    // All of them forward to `sui.nui.ViewSource`. C may ask before `setApp`
    // has run, so a source always exists: its accessors already answer "" / 0
    // / false for a null node, which is what these returned before.

    static function reader():sui.nui.ViewSource {
        if (_source == null) _source = new sui.nui.ViewSource(null);
        return _source;
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
        if (node == null) return "";
        var content:Dynamic = Reflect.field(node, "content");
        return content != null ? Std.string(content) : "";
    }

    /** Get the swift expression for state-interpolated text. **/
    public static function getTextExpression(node:View):String {
        if (node == null) return "";
        var expr:Dynamic = Reflect.field(node, "swiftExpression");
        if (expr == null) expr = Reflect.field(node, "composeExpression");
        return expr != null ? Std.string(expr) : "";
    }

    // --- Button special accessors ---

    /** Get button label. **/
    public static function getButtonLabel(node:View):String {
        if (node == null) return "";
        var label:Dynamic = Reflect.field(node, "label");
        return label != null ? Std.string(label) : "";
    }

    /** Get button action ID (for invoking via bridge). **/
    public static function getButtonActionId(node:View):Int {
        return reader().actionId(node);
    }

    /** Invoke a Button's action closure directly.

        The static bridge routes taps through an integer id into the Callbacks
        store because a Haxe closure captured by a Swift/ARC closure is invisible
        to the hxcpp GC. The dynamic renderer has no such problem: it holds the
        live view tree (`_root`, a GC root), so the closure sitting on the node
        stays reachable. So we just call it — no id, no Callbacks indirection. **/
    public static function invokeButtonAction(node:View):Void {
        reader().invokeAction(node);
    }
}
