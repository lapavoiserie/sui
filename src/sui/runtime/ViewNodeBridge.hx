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
**/
@:keep
class ViewNodeBridge {
    /** The root view tree, rebuilt on each reload. **/
    static var _root:View = null;

    /** Current app instance. **/
    static var _app:Dynamic = null;

    /** Set the app instance and build the initial view tree. **/
    public static function setApp(app:Dynamic):Void {
        _app = app;
        rebuild();
    }

    /** Rebuild the view tree by calling body() on the app. **/
    public static function rebuild():Void {
        if (_app != null) {
            _root = _app.body();
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

    /** Get the root view node. Returns an opaque pointer. **/
    public static function getRoot():View {
        return _root;
    }

    // --- View node accessors (called from C bridge) ---

    /** Get the viewType string (e.g., "VStack", "Text", "Button"). **/
    public static function getViewType(node:View):String {
        if (node == null) return "";
        // Strip package prefix: "sui.ui.VStack" → "VStack"
        var vt = node.viewType;
        if (vt == null) return "";
        var dot = vt.lastIndexOf(".");
        return dot >= 0 ? vt.substr(dot + 1) : vt;
    }

    /** Get the number of children. **/
    public static function getChildCount(node:View):Int {
        if (node == null || node.children == null) return 0;
        return node.children.length;
    }

    /** Get a child by index. **/
    public static function getChild(node:View, index:Int):View {
        if (node == null || node.children == null || index < 0 || index >= node.children.length) return null;
        return node.children[index];
    }

    /** Get a string property (e.g., "label", "content", "placeholder"). **/
    public static function getStringProperty(node:View, key:String):String {
        if (node == null || node.properties == null) return "";
        var val:Dynamic = node.properties.get(key);
        return val != null ? Std.string(val) : "";
    }

    /** Get an int property. **/
    public static function getIntProperty(node:View, key:String):Int {
        if (node == null || node.properties == null) return 0;
        var val:Dynamic = node.properties.get(key);
        return val != null ? cast(val, Int) : 0;
    }

    /** Get a float property. **/
    public static function getFloatProperty(node:View, key:String):Float {
        if (node == null || node.properties == null) return 0.0;
        var val:Dynamic = node.properties.get(key);
        return val != null ? cast(val, Float) : 0.0;
    }

    /** Get a bool property. **/
    public static function getBoolProperty(node:View, key:String):Bool {
        if (node == null || node.properties == null) return false;
        var val:Dynamic = node.properties.get(key);
        return val != null ? cast(val, Bool) : false;
    }

    /** Check if a property exists. **/
    public static function hasProperty(node:View, key:String):Bool {
        if (node == null || node.properties == null) return false;
        return node.properties.exists(key);
    }

    /** Get the number of modifiers. **/
    public static function getModifierCount(node:View):Int {
        if (node == null || node.modifierChain == null) return 0;
        return node.modifierChain.length;
    }

    /** Get modifier type name at index. **/
    public static function getModifierType(node:View, index:Int):String {
        if (node == null || node.modifierChain == null || index < 0 || index >= node.modifierChain.length) return "";
        return Type.enumConstructor(node.modifierChain[index]);
    }

    /** Get modifier float parameter (e.g., padding value, opacity). **/
    public static function getModifierFloat(node:View, index:Int, paramIndex:Int):Float {
        if (node == null || node.modifierChain == null || index < 0 || index >= node.modifierChain.length) return 0.0;
        var params = Type.enumParameters(node.modifierChain[index]);
        if (paramIndex < 0 || paramIndex >= params.length) return 0.0;
        var val:Dynamic = params[paramIndex];
        if (Std.isOfType(val, Float)) return val;
        if (Std.isOfType(val, Int)) return cast(val, Int) * 1.0;
        return 0.0;
    }

    /** Get modifier string parameter (e.g., color name, font style). **/
    public static function getModifierString(node:View, index:Int, paramIndex:Int):String {
        if (node == null || node.modifierChain == null || index < 0 || index >= node.modifierChain.length) return "";
        var params = Type.enumParameters(node.modifierChain[index]);
        if (paramIndex < 0 || paramIndex >= params.length) return "";
        return Std.string(params[paramIndex]);
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
        if (node == null) return -1;
        var id:Dynamic = Reflect.field(node, "actionId");
        return id != null ? cast(id, Int) : -1;
    }

    /** Invoke a Button's action closure directly.

        The static bridge routes taps through an integer id into the Callbacks
        store because a Haxe closure captured by a Swift/ARC closure is invisible
        to the hxcpp GC. The dynamic renderer has no such problem: it holds the
        live view tree (`_root`, a GC root), so the closure sitting on the node
        stays reachable. So we just call it — no id, no Callbacks indirection. **/
    public static function invokeButtonAction(node:View):Void {
        if (node == null) return;
        var action:Dynamic = Reflect.field(node, "action");
        if (action != null) action();
    }
}
