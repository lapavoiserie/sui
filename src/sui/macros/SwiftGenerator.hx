package sui.macros;

#if macro
import haxe.macro.Context;
#end

using StringTools;

/**
    Compile-time macro that generates Swift/SwiftUI source files from the Haxe view DSL.
    Runs during `haxe build.hxml` via `--macro sui.macros.SwiftGenerator.register()`.
    No binary execution needed — Swift files are emitted as a side effect of compilation.
**/
class SwiftGenerator {

    /** Hook into the Haxe compiler. Called via --macro in build.hxml. **/
    public static function register() {
        #if macro
        var outputDir = Context.defined("swift-output") ? Context.definedValue("swift-output") : "build/swift";

        Context.onGenerate(function(types:Array<haxe.macro.Type>) {
            // First pass: collect Observable structs and ViewComponent types
            var modelTypes = new Map<String, haxe.macro.Type.ClassType>();
            var componentTypes = new Map<String, haxe.macro.Type.ClassType>();
            for (type in types) {
                switch (type) {
                    case TInst(classRef, _):
                        var cls = classRef.get();
                        if (isObservableSubclass(cls))
                            modelTypes.set(cls.name, cls);
                        if (isViewComponentSubclass(cls))
                            componentTypes.set(cls.name, cls);
                    default:
                }
            }

            // Second pass: generate Swift for App subclasses
            for (type in types) {
                switch (type) {
                    case TInst(classRef, _):
                        var cls = classRef.get();
                        if (isAppSubclass(cls)) {
                            generateSwift(cls, outputDir, modelTypes, componentTypes);
                        }
                    default:
                }
            }
        });
        #end
    }

    #if macro

    // ── Type detection ──────────────────────────────────────────────

    static function isAppSubclass(cls:haxe.macro.Type.ClassType):Bool {
        if (cls.name == "App" && cls.pack.join(".") == "sui") return false;
        var sc = cls.superClass;
        while (sc != null) {
            var scCls = sc.t.get();
            if (scCls.name == "App" && scCls.pack.join(".") == "sui") return true;
            sc = scCls.superClass;
        }
        return false;
    }

    static function isObservableSubclass(cls:haxe.macro.Type.ClassType):Bool {
        if (cls.name == "Observable" && cls.pack.join(".") == "sui.state") return false;
        var sc = cls.superClass;
        while (sc != null) {
            var scCls = sc.t.get();
            if (scCls.name == "Observable" && scCls.pack.join(".") == "sui.state") return true;
            sc = scCls.superClass;
        }
        return false;
    }

    static function isValidStateType(type:haxe.macro.Type):Bool {
        switch (type) {
            case TAbstract(absRef, _):
                var name = absRef.get().name;
                if (name == "Int" || name == "Float" || name == "Bool") return true;
                return false;
            case TInst(classRef, params):
                var cls = classRef.get();
                if (cls.name == "String" && cls.pack.length == 0) return true;
                if (cls.name == "Array" && params.length > 0) return isValidStateType(params[0]);
                return isObservableSubclass(cls);
            default:
                return false;
        }
    }

    static function isViewComponentSubclass(cls:haxe.macro.Type.ClassType):Bool {
        if (cls.name == "ViewComponent" && cls.pack.join(".") == "sui") return false;
        var sc = cls.superClass;
        while (sc != null) {
            var scCls = sc.t.get();
            if (scCls.name == "ViewComponent" && scCls.pack.join(".") == "sui") return true;
            sc = scCls.superClass;
        }
        return false;
    }

    // ── Main generation ─────────────────────────────────────────────

    static function generateSwift(cls:haxe.macro.Type.ClassType, outputDir:String, ?modelTypes:Map<String, haxe.macro.Type.ClassType>, ?componentTypes:Map<String, haxe.macro.Type.ClassType>):Void {
        var className = cls.name;
        var appName = className;
        var bundleId = 'com.example.${className.toLowerCase()}';
        localBindings = new Map();
        needsRuntimeBridge = false;
        needsHorizontalSizeClass = false;
        nextActionId = 0;

        // 1. Find State<T> fields
        var stateDecls:Array<{name:String, swiftType:String, defaultValue:String}> = [];
        for (field in cls.fields.get()) {
            switch (field.type) {
                case TInst(ref, params):
                    if (ref.get().name == "State" && ref.get().pack.join(".") == "sui.state" && params.length > 0) {
                        if (!isValidStateType(params[0])) {
                            var st = haxeTypeToSwift(params[0]);
                            Context.error('[SwiftGen] State<${st}> is not supported. Use a basic type (Int, Float, Bool, String), an array of basic types, or a class extending Observable.', field.pos);
                        }
                        var st = haxeTypeToSwift(params[0]);
                        stateDecls.push({name: field.name, swiftType: st, defaultValue: swiftDefault(st)});
                    }
                default:
            }
        }

        // 2. Walk constructor for appName, bundleId, state inits
        if (cls.constructor != null) {
            var ctorExpr = cls.constructor.get().expr();
            if (ctorExpr != null) walkCtor(ctorExpr, stateDecls, function(n:String, v:String) {
                if (n == "appName") appName = v;
                else if (n == "bundleIdentifier") bundleId = v;
            });
        }

        // 3. Pre-detect @:expose / @:bridge methods
        for (field in cls.statics.get()) {
            if (field.meta.has(":bridge")) {
                Context.warning('@:bridge is deprecated, use @:expose instead', field.pos);
                needsRuntimeBridge = true;
            }
            if (field.meta.has(":expose")) needsRuntimeBridge = true;
        }

        // 4. Walk body() method (may also set needsRuntimeBridge for complex closures)
        var bodySwift = "        // empty body\n";
        var commandsSwift = "";
        var settingsSwift = "";
        for (field in cls.fields.get()) {
            if (field.name == "body") {
                var expr = field.expr();
                if (expr != null)
                    bodySwift = walkFunc(expr, 2);
            } else if (field.name == "commands") {
                // Walk `commands()` to find its returned TArrayDecl of
                // `new CommandMenu(...)` values. Render each via
                // `viewToSwift` and stitch them into a single
                // `.commands { … }` block attached to WindowGroup.
                var expr = field.expr();
                if (expr != null) commandsSwift = walkCommandsFunc(expr);
            } else if (field.name == "settings") {
                var expr = field.expr();
                if (expr != null) settingsSwift = walkFunc(expr, 2);
            }
        }
        // The default `settings()` returns `new View()`, which
        // `viewToSwift` renders as a "Unknown view" placeholder
        // comment. Treat that as "user didn't override" and skip
        // emitting the Settings scene altogether.
        var hasSettings = settingsSwift != "" && settingsSwift.indexOf("Unknown view") == -1;
        // The Settings scene only makes sense if its preferences
        // share state with the rest of the app — `Toggle("Dark Mode",
        // "darkMode")` in Settings must read/write the same value
        // ContentView observes. Force the bridged AppState path so
        // both view structs reference `AppState.shared` rather than
        // each carrying its own private `@State` copies.
        if (hasSettings) needsRuntimeBridge = true;

        // 5. Emit App.swift (after needsRuntimeBridge is finalized)
        var appSwift = new StringBuf();
        appSwift.add("import SwiftUI\n\n");
        appSwift.add("@main\n");
        appSwift.add('struct ${className}App: App {\n');
        appSwift.add("    init() {\n");
        if (needsRuntimeBridge) {
            // Register the swift-side state callback BEFORE the
            // runtime boots. `HaxeRuntime.initialize()` calls
            // `haxe_bridge_init`, which itself constructs the
            // application class — any `State.setByName` (or
            // `State<T>(initialValue, ...)` push) issued during the
            // constructor only reaches AppState if the swift
            // callback is already wired up. With the previous order
            // those updates were dropped silently and AppState
            // stayed on its literal defaults until the next mutation.
            appSwift.add("        HaxeBridgeC.registerCallbacks()\n");
        }
        appSwift.add("        HaxeRuntime.initialize()\n");
        appSwift.add("    }\n\n");
        // The `commands` block lives at Scene level, not inside a
        // View — so `appState.X` references inside StateActions can't
        // resolve through ContentView's `@Bindable var appState`.
        // Inject the same declaration into the App struct so the
        // commands closures see it.
        var needsAppStateInApp = (commandsSwift != "" || hasSettings)
            && needsRuntimeBridge && stateDecls.length > 0;
        if (needsAppStateInApp) {
            appSwift.add("\n    @Bindable var appState = AppState.shared\n");
        }
        appSwift.add("\n    var body: some Scene {\n");
        appSwift.add('        WindowGroup("${esc(appName)}") {\n');
        appSwift.add("            ContentView()\n");
        appSwift.add("        }\n");
        if (commandsSwift != "") {
            var emitted = needsAppStateInApp
                ? rewriteStateRefsToAppState(commandsSwift, stateDecls)
                : commandsSwift;
            appSwift.add("        .commands {\n");
            appSwift.add(emitted);
            appSwift.add("        }\n");
        }
        if (hasSettings) {
            appSwift.add("        #if os(macOS)\n");
            appSwift.add("        Settings {\n");
            appSwift.add("            SettingsView()\n");
            appSwift.add("        }\n");
            appSwift.add("        #endif\n");
        }
        appSwift.add("    }\n");
        appSwift.add("}\n");

        // 5. Emit ContentView.swift
        var viewSwift = new StringBuf();
        viewSwift.add("import SwiftUI\n");
        if (bodySwift.indexOf("Model3D") != -1 || bodySwift.indexOf("RealityView") != -1)
            viewSwift.add("import RealityKit\n");
        viewSwift.add("\n");
        viewSwift.add("struct ContentView: View {\n");

        if (needsRuntimeBridge && stateDecls.length > 0) {
            // Bridged mode: use AppState observable
            viewSwift.add("    @Bindable var appState = AppState.shared\n\n");
        } else {
            // Standalone mode: use @State
            for (sd in stateDecls)
                viewSwift.add('    @State private var ${sd.name}: ${sd.swiftType} = ${sd.defaultValue}\n');
            if (stateDecls.length > 0) viewSwift.add("\n");
        }

        if (needsHorizontalSizeClass)
            viewSwift.add("    @Environment(\\.horizontalSizeClass) private var horizontalSizeClass\n\n");

        viewSwift.add("    var body: some View {\n");

        if (needsRuntimeBridge && stateDecls.length > 0) {
            viewSwift.add(rewriteStateRefsToAppState(bodySwift, stateDecls));
        } else {
            viewSwift.add(bodySwift);
        }

        viewSwift.add("    }\n");
        viewSwift.add("}\n");

        // 5b. Optionally emit a SettingsView struct alongside ContentView.
        //     Same `@Bindable var appState` (or `@State`s) wiring so it
        //     can read/write the same app-wide state.
        if (hasSettings) {
            viewSwift.add("\n");
            viewSwift.add("struct SettingsView: View {\n");
            if (needsRuntimeBridge && stateDecls.length > 0) {
                viewSwift.add("    @Bindable var appState = AppState.shared\n\n");
            } else {
                for (sd in stateDecls)
                    viewSwift.add('    @State private var ${sd.name}: ${sd.swiftType} = ${sd.defaultValue}\n');
                if (stateDecls.length > 0) viewSwift.add("\n");
            }
            viewSwift.add("    var body: some View {\n");
            if (needsRuntimeBridge && stateDecls.length > 0) {
                viewSwift.add(rewriteStateRefsToAppState(settingsSwift, stateDecls));
            } else {
                viewSwift.add(settingsSwift);
            }
            viewSwift.add("    }\n");
            viewSwift.add("}\n");
        }

        // 6. Generate model structs for Observable subclasses used by this app
        var modelSwift = new StringBuf();
        if (modelTypes != null) {
            for (modelName in modelTypes.keys()) {
                // Check if any state decl references this model type
                var used = false;
                for (sd in stateDecls) {
                    if (sd.swiftType.indexOf(modelName) != -1) { used = true; break; }
                }
                if (used) {
                    var modelCls = modelTypes.get(modelName);
                    modelSwift.add(generateModelStruct(modelCls));
                    modelSwift.add("\n");
                }
            }
        }

        // 7. Detect @:expose / @:bridge static methods → generate C header + Swift wrapper
        var bridgeFunctions:Array<{name:String, params:Array<{name:String, swiftType:String}>, returnType:String}> = [];
        for (field in cls.statics.get()) {
            if (field.meta.has(":expose") || field.meta.has(":bridge")) {
                var params:Array<{name:String, swiftType:String}> = [];
                var retType = "Void";
                switch (field.type) {
                    case TFun(fnArgs, ret):
                        for (a in fnArgs)
                            params.push({name: a.name, swiftType: haxeTypeToSwift(a.t)});
                        retType = haxeTypeToSwift(ret);
                    default:
                }
                bridgeFunctions.push({name: field.name, params: params, returnType: retType});
            }
        }

        // 8. Write files
        ensureDir(outputDir);
        sys.io.File.saveContent('$outputDir/App.swift', appSwift.toString());

        var contentWithModels = new StringBuf();
        contentWithModels.add(viewSwift.toString());
        if (modelSwift.toString().length > 0) {
            contentWithModels.add("\n");
            contentWithModels.add(modelSwift.toString());
        }
        sys.io.File.saveContent('$outputDir/ContentView.swift', contentWithModels.toString());

        // Write bridge files if bridge is needed (explicit @:bridge or runtime closures)
        if (needsRuntimeBridge || bridgeFunctions.length > 0) {
            sys.io.File.saveContent('$outputDir/HaxeBridgeC.h', generateBridgeHeader(bridgeFunctions, needsRuntimeBridge));
            sys.io.File.saveContent('$outputDir/HaxeBridgeC.cpp', generateBridgeCpp(className, bridgeFunctions, needsRuntimeBridge));
            sys.io.File.saveContent('$outputDir/HaxeBridgeC.swift', generateBridgeSwift(className, bridgeFunctions, needsRuntimeBridge));
        }

        // Generate AppState.swift for bridged apps with state
        if (needsRuntimeBridge && stateDecls.length > 0) {
            sys.io.File.saveContent('$outputDir/AppState.swift', generateAppState(stateDecls));
        }

        // Generate Swift structs for ViewComponent subclasses
        if (componentTypes != null) {
            for (compName in componentTypes.keys()) {
                var compCls = componentTypes.get(compName);
                var compSwift = generateComponent(compCls);
                if (compSwift != null) {
                    sys.io.File.saveContent('$outputDir/$compName.swift', compSwift);
                }
            }
        }
    }

    /** Rewrite the bare state names produced by `viewToSwift` /
        StateAction emission so they target the bridged `appState.X`
        object. The codepath that emits Swift assumes everything will
        be hoisted under a `@Bindable var appState = AppState.shared`
        — but the emitter doesn't know that yet, so we patch the
        identifiers in a single textual pass. Run this on every
        chunk that lives in a struct holding `appState`: the
        ContentView body, the SettingsView body, and (for
        scene-level constructs like `.commands { … }`) the App
        struct's body. **/
    static function rewriteStateRefsToAppState(s:String, stateDecls:Array<{name:String, swiftType:String, defaultValue:String}>):String {
        var placeholder = "__APPSTATE__";
        for (sd in stateDecls) {
            var n = sd.name;
            // `$name` (Swift binding)
            s = StringTools.replace(s, "$" + n, "$" + placeholder + n);
            // `\(name)` (Swift string interpolation)
            s = StringTools.replace(s, '\\(' + n + ')', '\\(' + placeholder + n + ')');
            // `{name}` (bridge call argument templates)
            s = StringTools.replace(s, "{" + n + "}", '\\(' + placeholder + n + ')');
            // `name = ` (assignment inside closures)
            s = StringTools.replace(s, n + " = ", placeholder + n + " = ");
            // `if name ` / `if name\n` (ConditionalView boolean)
            s = StringTools.replace(s, "if " + n + " ", "if " + placeholder + n + " ");
            s = StringTools.replace(s, "if " + n + "\n", "if " + placeholder + n + "\n");
            // `0..<name.count` (ForEach iteration header)
            s = StringTools.replace(s, "0..<" + n + ".count", "0..<" + placeholder + n + ".count");
            // `ForEach(name,` (closure-form ForEach over a state array)
            s = StringTools.replace(s, "ForEach(" + n + ",", "ForEach(" + placeholder + n + ",");
            // `(name[` `!name[` ` name[` `=name[` (subscript-access
            // shapes that show up inside CustomSwift / interpolation
            // bodies). Each lookbehind is narrow enough to avoid
            // matching a state name that happens to be a suffix of a
            // longer identifier.
            s = StringTools.replace(s, "(" + n + "[", "(" + placeholder + n + "[");
            s = StringTools.replace(s, "!" + n + "[", "!" + placeholder + n + "[");
            s = StringTools.replace(s, " " + n + "[", " " + placeholder + n + "[");
            s = StringTools.replace(s, "=" + n + "[", "=" + placeholder + n + "[");
        }
        return StringTools.replace(s, placeholder, "appState.");
    }

    /** Generate an @Observable AppState class for bridged state management. **/
    static function generateAppState(stateDecls:Array<{name:String, swiftType:String, defaultValue:String}>):String {
        var buf = new StringBuf();
        buf.add("import Foundation\nimport Observation\n\n");
        buf.add("@Observable\n");
        buf.add("class AppState {\n");
        buf.add("    static let shared = AppState()\n\n");
        for (sd in stateDecls) {
            if (sd.swiftType.charAt(0) == "[") {
                // Array types: computed property that queries hxcpp shared memory
                var innerType = sd.swiftType.substring(1, sd.swiftType.length - 1);
                var accessor = switch (innerType) {
                    case "Int": "arrayIntElement";
                    case "Double": "arrayFloatElement";
                    case "Bool": "arrayBoolElement";
                    default: "arrayStringElement";
                };
                buf.add('    var ${sd.name}: ${sd.swiftType} {\n');
                buf.add('        let _ = _${sd.name}Version // subscribe to changes\n');
                buf.add('        let count = HaxeBridgeC.arrayLength("${sd.name}")\n');
                buf.add('        guard count > 0 else { return [] }\n');
                buf.add('        return (0..<count).map { HaxeBridgeC.${accessor}("${sd.name}", at: $$0) }\n');
                buf.add("    }\n");
                buf.add('    var _${sd.name}Version: Int = 0\n\n');
            } else {
                buf.add('    var ${sd.name}: ${sd.swiftType} = ${sd.defaultValue}\n');
            }
        }
        buf.add("\n    func set(_ key: String, _ value: String) {\n");
        buf.add("        switch key {\n");
        for (sd in stateDecls) {
            if (sd.swiftType.charAt(0) == "[") {
                // Array types: bump version counter to trigger SwiftUI re-render
                buf.add('        case "${sd.name}": _${sd.name}Version += 1\n');
            } else {
                switch (sd.swiftType) {
                    case "Int": buf.add('        case "${sd.name}": ${sd.name} = Int(value) ?? 0\n');
                    case "Double": buf.add('        case "${sd.name}": ${sd.name} = Double(value) ?? 0.0\n');
                    case "Bool": buf.add('        case "${sd.name}": ${sd.name} = value == "true"\n');
                    default: buf.add('        case "${sd.name}": ${sd.name} = value\n');
                }
            }
        }
        buf.add("        default: break\n");
        buf.add("        }\n");
        buf.add("    }\n");
        buf.add("}\n");
        return buf.toString();
    }

    /** Generate a Swift View struct from a ViewComponent subclass. **/
    static function generateComponent(cls:haxe.macro.Type.ClassType):String {
        localBindings = new Map();

        var buf = new StringBuf();
        buf.add("import SwiftUI\n\n");
        buf.add('struct ${cls.name}: View {\n');

        // Generate properties from constructor parameters
        // For @:binding params, look up the real type from the class field
        if (cls.constructor != null) {
            var ctor = cls.constructor.get();
            var paramInfo = getParamInfo(ctor);

            switch (ctor.type) {
                case TFun(fnArgs, _):
                    for (i in 0...fnArgs.length) {
                        var arg = fnArgs[i];
                        var isBinding = i < paramInfo.length && paramInfo[i].isBinding;

                        if (isBinding) {
                            // Look up real type from class field with @:binding metadata
                            var realType = "String";
                            for (field in cls.fields.get()) {
                                if (field.name == arg.name && field.meta.has(":swiftBinding")) {
                                    realType = haxeTypeToSwift(field.type);
                                    break;
                                }
                            }
                            buf.add('    @Binding var ${arg.name}: ${realType}\n');
                        } else {
                            var swiftType = haxeTypeToSwift(arg.t);
                            buf.add('    let ${arg.name}: ${swiftType}\n');
                        }
                    }
                default:
            }
        }

        // In bridge/AppState mode, give components access to shared state
        if (needsRuntimeBridge) {
            buf.add("    @Bindable var appState = AppState.shared\n");
        }

        buf.add("\n");

        // Generate body
        buf.add("    var body: some View {\n");
        for (field in cls.fields.get()) {
            if (field.name == "body") {
                var expr = field.expr();
                if (expr != null)
                    buf.add(walkFunc(expr, 2));
                break;
            }
        }
        buf.add("    }\n");
        buf.add("}\n");

        return buf.toString();
    }

    // ── Bridge generation ───────────────────────────────────────────

    static function swiftTypeToCType(t:String):String {
        return switch (t) {
            case "Int": "int32_t";
            case "Double" | "Float": "double";
            case "Bool": "bool";
            case "String": "const char*";
            case "Void": "void";
            default: "void*";
        }
    }

    static function generateBridgeHeader(fns:Array<{name:String, params:Array<{name:String, swiftType:String}>, returnType:String}>, hasRuntimeActions:Bool):String {
        var buf = new StringBuf();
        buf.add("#ifndef HAXE_BRIDGE_C_H\n#define HAXE_BRIDGE_C_H\n\n");
        buf.add("#include <stdint.h>\n#include <stdbool.h>\n\n");
        buf.add("#ifdef __cplusplus\nextern \"C\" {\n#endif\n\n");
        buf.add("void haxe_bridge_init(void);\n\n");

        if (hasRuntimeActions) {
            buf.add("// Invoke a registered button action by ID\n");
            buf.add("void haxe_bridge_invoke_action(int32_t actionId);\n\n");
            buf.add("// State callback: called by Haxe when State.set() is invoked\n");
            buf.add("typedef void (*haxe_state_callback_t)(const char* key, const char* value);\n");
            buf.add("void haxe_bridge_register_state_callback(haxe_state_callback_t callback);\n\n");
        }

        // Shared-memory query functions
        buf.add("// Query array state from hxcpp shared memory\n");
        buf.add("int32_t haxe_bridge_array_length(const char* stateName);\n");
        buf.add("const char* haxe_bridge_array_string_element(const char* stateName, int32_t index);\n");
        buf.add("int32_t haxe_bridge_array_int_element(const char* stateName, int32_t index);\n");
        buf.add("double haxe_bridge_array_float_element(const char* stateName, int32_t index);\n");
        buf.add("bool haxe_bridge_array_bool_element(const char* stateName, int32_t index);\n\n");
        buf.add("// Query object fields from array elements\n");
        buf.add("const char* haxe_bridge_object_field(const char* stateName, int32_t index, const char* fieldName);\n");
        buf.add("int32_t haxe_bridge_object_int_field(const char* stateName, int32_t index, const char* fieldName);\n");
        buf.add("double haxe_bridge_object_float_field(const char* stateName, int32_t index, const char* fieldName);\n");
        buf.add("bool haxe_bridge_object_bool_field(const char* stateName, int32_t index, const char* fieldName);\n\n");

        for (fn in fns) {
            var cParams = [for (p in fn.params) '${swiftTypeToCType(p.swiftType)} ${p.name}'];
            if (cParams.length == 0) cParams.push("void");
            buf.add('${swiftTypeToCType(fn.returnType)} haxe_bridge_${fn.name}(${cParams.join(", ")});\n');
        }
        buf.add("\n#ifdef __cplusplus\n}\n#endif\n\n#endif\n");
        return buf.toString();
    }

    /** Generate C++ bridge that calls into real hxcpp-compiled Haxe code. **/
    static function generateBridgeCpp(appClassName:String, fns:Array<{name:String, params:Array<{name:String, swiftType:String}>, returnType:String}>, hasRuntimeActions:Bool):String {
        var buf = new StringBuf();
        buf.add('#include "HaxeBridgeC.h"\n');
        buf.add("#include <hxcpp.h>\n");
        buf.add('#include "${appClassName}.h"\n');
        if (hasRuntimeActions) {
            buf.add('#include "sui/ui/Button.h"\n');
        }
        buf.add('#include "sui/state/State.h"\n');
        buf.add("#include <string.h>\n");
        buf.add("#include <mutex>\n");
        buf.add("#include <cstdio>\n\n");
        buf.add("// Auto-generated bridge: calls into hxcpp-compiled Haxe code.\n\n");

        buf.add("extern \"C\" void __hxcpp_lib_main() {}\n");

        if (hasRuntimeActions) {
            buf.add("// Forward declaration for State.cpp's registration function\n");
            buf.add("extern \"C\" void haxe_bridge_register_state_fn(void (*)(const char*, const char*));\n");
        }
        buf.add("\n");

        // ── Bridge safety scaffold ────────────────────────────────
        //
        // Every entry into this file ends up running hxcpp-compiled
        // Haxe code, which:
        //   1) requires the calling thread's stack to be registered as
        //      a GC root via hx::SetTopOfStack, and
        //   2) is *not* internally synchronized — two threads running
        //      Haxe at once is undefined behaviour.
        //
        // SwiftUI clients hit case 2 the moment they mix
        //   - computed properties that query state on every body re-eval
        //     (the closure form of ForEach lands here), and
        //   - `Task.detached { HaxeBridgeC.foo(...) }` for any user
        //     `@:expose`d function.
        //
        // We serialize both with a single global recursive_mutex.
        // Recursive is necessary because Haxe→Swift callbacks
        // (`_bridge_state_forwarder`) can in turn invoke other bridge
        // entrypoints, all on the same thread.
        //
        // Each entrypoint also wraps the call in try/catch — an
        // uncaught Haxe `throw` walks past `__cxa_throw` and aborts
        // the process; without the catch we have no way to surface
        // the error to Swift.
        buf.add("static std::recursive_mutex _haxe_runtime_mutex;\n\n");

        buf.add("struct HaxeBridgeScope {\n");
        buf.add("    std::lock_guard<std::recursive_mutex> _lock;\n");
        buf.add("    int _gc_dummy;\n");
        buf.add("    HaxeBridgeScope() : _lock(_haxe_runtime_mutex), _gc_dummy(0) {\n");
        buf.add("        hx::SetTopOfStack(&_gc_dummy, true);\n");
        buf.add("    }\n");
        buf.add("    ~HaxeBridgeScope() {\n");
        buf.add("        hx::SetTopOfStack((int*)0, true);\n");
        buf.add("    }\n");
        buf.add("};\n\n");

        if (hasRuntimeActions) {
            // State callback: Swift → C → Haxe State.set() → C → Swift AppState
            buf.add("static haxe_state_callback_t _swift_state_cb = nullptr;\n\n");
            buf.add("void haxe_bridge_register_state_callback(haxe_state_callback_t callback) {\n");
            buf.add("    _swift_state_cb = callback;\n");
            buf.add("}\n\n");

            // Forward to Swift when Haxe State.set() fires
            buf.add("static void _bridge_state_forwarder(const char* key, const char* value) {\n");
            buf.add("    if (_swift_state_cb) _swift_state_cb(key, value);\n");
            buf.add("}\n\n");
        }

        // haxe_bridge_init: boots hxcpp runtime, registers callbacks, builds view tree.
        // Boot itself isn't reentrant, so we hold the lock for the whole init body.
        buf.add("void haxe_bridge_init(void) {\n");
        buf.add("    std::lock_guard<std::recursive_mutex> _lock(_haxe_runtime_mutex);\n");
        buf.add("    int dummy = 0;\n");
        buf.add("    hx::SetTopOfStack(&dummy, true);\n");
        buf.add("    try {\n");
        buf.add("        hx::Boot();\n");
        buf.add("        __boot_all();\n");
        if (hasRuntimeActions) {
            buf.add("        // Register state change forwarder (State.set() → Swift AppState)\n");
            buf.add("        haxe_bridge_register_state_fn(_bridge_state_forwarder);\n");
            buf.add("        // Build view tree to register button actions\n");
            buf.add('        auto app = ::${appClassName}_obj::__new();\n');
            buf.add("        app->body();\n");
        }
        buf.add("    } catch (::Dynamic _e) {\n");
        buf.add('        fprintf(stderr, "[sui] haxe_bridge_init: Haxe exception during boot\\n");\n');
        buf.add("    } catch (...) {\n");
        buf.add('        fprintf(stderr, "[sui] haxe_bridge_init: C++ exception during boot\\n");\n');
        buf.add("    }\n");
        buf.add("}\n\n");

        if (hasRuntimeActions) {
            // invoke_action: calls into Haxe Button action registry
            buf.add("void haxe_bridge_invoke_action(int32_t actionId) {\n");
            buf.add("    HaxeBridgeScope _scope;\n");
            buf.add("    try {\n");
            buf.add("        ::sui::ui::Button_obj::_invokeAction(actionId);\n");
            buf.add("    } catch (::Dynamic _e) {\n");
            buf.add('        fprintf(stderr, "[sui] haxe_bridge_invoke_action: Haxe exception\\n");\n');
            buf.add("    } catch (...) {\n");
            buf.add('        fprintf(stderr, "[sui] haxe_bridge_invoke_action: C++ exception\\n");\n');
            buf.add("    }\n");
            buf.add("}\n\n");
        }

        // ── Shared-memory query functions ─────────────────────────
        emitSharedMemoryReader(buf, "haxe_bridge_array_length",
            "int32_t", "0",
            "if (!stateName) return -1;\n",
            "(int32_t)::sui::state::State_obj::_getArrayLength(::String(stateName))",
            "stateName.c_str", null,
            "int32_t");

        emitSharedMemoryReader(buf, "haxe_bridge_array_string_element",
            "const char*", "\"\"",
            "if (!stateName) return \"\";\n",
            "::sui::state::State_obj::_getArrayStringElement(::String(stateName), (int)index)",
            "stateName.c_str + index", "haxe_string_to_buf",
            "::String");

        emitSharedMemoryReader(buf, "haxe_bridge_array_int_element",
            "int32_t", "0",
            "if (!stateName) return 0;\n",
            "(int32_t)::sui::state::State_obj::_getArrayIntElement(::String(stateName), (int)index)",
            "stateName.c_str + index", null,
            "int32_t");

        emitSharedMemoryReader(buf, "haxe_bridge_array_float_element",
            "double", "0.0",
            "if (!stateName) return 0.0;\n",
            "(double)::sui::state::State_obj::_getArrayFloatElement(::String(stateName), (int)index)",
            "stateName.c_str + index", null,
            "double");

        emitSharedMemoryReader(buf, "haxe_bridge_array_bool_element",
            "bool", "false",
            "if (!stateName) return false;\n",
            "(bool)::sui::state::State_obj::_getArrayBoolElement(::String(stateName), (int)index)",
            "stateName.c_str + index", null,
            "bool");

        emitSharedMemoryReader(buf, "haxe_bridge_object_field",
            "const char*", "\"\"",
            "if (!stateName || !fieldName) return \"\";\n",
            "::sui::state::State_obj::_getObjectField(::String(stateName), (int)index, ::String(fieldName))",
            "stateName.c_str + index + fieldName.c_str", "haxe_string_to_buf",
            "::String");

        emitSharedMemoryReader(buf, "haxe_bridge_object_int_field",
            "int32_t", "0",
            "if (!stateName || !fieldName) return 0;\n",
            "(int32_t)::sui::state::State_obj::_getObjectIntField(::String(stateName), (int)index, ::String(fieldName))",
            "stateName.c_str + index + fieldName.c_str", null,
            "int32_t");

        emitSharedMemoryReader(buf, "haxe_bridge_object_float_field",
            "double", "0.0",
            "if (!stateName || !fieldName) return 0.0;\n",
            "(double)::sui::state::State_obj::_getObjectFloatField(::String(stateName), (int)index, ::String(fieldName))",
            "stateName.c_str + index + fieldName.c_str", null,
            "double");

        emitSharedMemoryReader(buf, "haxe_bridge_object_bool_field",
            "bool", "false",
            "if (!stateName || !fieldName) return false;\n",
            "(bool)::sui::state::State_obj::_getObjectBoolField(::String(stateName), (int)index, ::String(fieldName))",
            "stateName.c_str + index + fieldName.c_str", null,
            "bool");

        // ── User-defined @:expose functions ───────────────────────
        for (fn in fns) {
            var cParams = [for (p in fn.params) '${swiftTypeToCType(p.swiftType)} ${p.name}'];
            if (cParams.length == 0) cParams.push("void");
            var cReturnType = swiftTypeToCType(fn.returnType);
            buf.add('$cReturnType haxe_bridge_${fn.name}(${cParams.join(", ")}) {\n');

            // Build hxcpp call arguments
            var hxArgs:Array<String> = [];
            for (p in fn.params) {
                switch (p.swiftType) {
                    case "String": hxArgs.push('::String(${p.name})');
                    case "Int": hxArgs.push('(int)${p.name}');
                    case "Double" | "Float": hxArgs.push('(double)${p.name}');
                    case "Bool": hxArgs.push('(bool)${p.name}');
                    default: hxArgs.push(p.name);
                }
            }

            var call = '::${appClassName}_obj::${fn.name}(${hxArgs.join(", ")})';
            var fnName = fn.name;

            switch (fn.returnType) {
                case "String":
                    buf.add('    static thread_local char _buf[4096];\n');
                    buf.add('    _buf[0] = 0;\n');
                    buf.add('    {\n');
                    buf.add('        HaxeBridgeScope _scope;\n');
                    buf.add('        try {\n');
                    buf.add('            ::String _hx_result = $call;\n');
                    buf.add('            const char* _cstr = _hx_result.__CStr();\n');
                    buf.add('            strncpy(_buf, _cstr, sizeof(_buf) - 1);\n');
                    buf.add('            _buf[sizeof(_buf) - 1] = 0;\n');
                    buf.add('        } catch (::Dynamic _e) {\n');
                    buf.add('            fprintf(stderr, "[sui] haxe_bridge_$fnName: Haxe exception\\n");\n');
                    buf.add('        } catch (...) {\n');
                    buf.add('            fprintf(stderr, "[sui] haxe_bridge_$fnName: C++ exception\\n");\n');
                    buf.add('        }\n');
                    buf.add('    }\n');
                    buf.add('    return _buf;\n');
                case "Int":
                    buf.add('    int32_t _ret = 0;\n');
                    buf.add('    {\n');
                    buf.add('        HaxeBridgeScope _scope;\n');
                    buf.add('        try { _ret = (int32_t)$call; }\n');
                    buf.add('        catch (::Dynamic _e) { fprintf(stderr, "[sui] haxe_bridge_$fnName: Haxe exception\\n"); }\n');
                    buf.add('        catch (...) { fprintf(stderr, "[sui] haxe_bridge_$fnName: C++ exception\\n"); }\n');
                    buf.add('    }\n');
                    buf.add('    return _ret;\n');
                case "Double" | "Float":
                    buf.add('    double _ret = 0.0;\n');
                    buf.add('    {\n');
                    buf.add('        HaxeBridgeScope _scope;\n');
                    buf.add('        try { _ret = (double)$call; }\n');
                    buf.add('        catch (::Dynamic _e) { fprintf(stderr, "[sui] haxe_bridge_$fnName: Haxe exception\\n"); }\n');
                    buf.add('        catch (...) { fprintf(stderr, "[sui] haxe_bridge_$fnName: C++ exception\\n"); }\n');
                    buf.add('    }\n');
                    buf.add('    return _ret;\n');
                case "Bool":
                    buf.add('    bool _ret = false;\n');
                    buf.add('    {\n');
                    buf.add('        HaxeBridgeScope _scope;\n');
                    buf.add('        try { _ret = (bool)$call; }\n');
                    buf.add('        catch (::Dynamic _e) { fprintf(stderr, "[sui] haxe_bridge_$fnName: Haxe exception\\n"); }\n');
                    buf.add('        catch (...) { fprintf(stderr, "[sui] haxe_bridge_$fnName: C++ exception\\n"); }\n');
                    buf.add('    }\n');
                    buf.add('    return _ret;\n');
                default:
                    buf.add('    HaxeBridgeScope _scope;\n');
                    buf.add('    try { $call; }\n');
                    buf.add('    catch (::Dynamic _e) { fprintf(stderr, "[sui] haxe_bridge_$fnName: Haxe exception\\n"); }\n');
                    buf.add('    catch (...) { fprintf(stderr, "[sui] haxe_bridge_$fnName: C++ exception\\n"); }\n');
            }

            buf.add("}\n\n");
        }
        return buf.toString();
    }

    /** Helper for the shared-memory state readers. They all share the
        same shape: a guard, a HaxeBridgeScope, a try/catch around the
        Haxe call, and either a numeric return or a thread-local
        buffer for String returns. The macro-level abstraction keeps
        the bridge body small and consistent. **/
    static function emitSharedMemoryReader(buf:StringBuf, fnName:String,
            cReturnType:String, defaultReturn:String, guard:String,
            call:String, _:String, stringMode:Null<String>, hxResultType:String):Void {
        var isString = (stringMode == "haxe_string_to_buf");
        // Reconstruct the C parameter list from the function name —
        // the naming convention is enough to discriminate.
        var params = if (fnName.indexOf("object") >= 0)
            "const char* stateName, int32_t index, const char* fieldName";
        else if (fnName.indexOf("element") >= 0)
            "const char* stateName, int32_t index";
        else
            "const char* stateName";
        buf.add('$cReturnType ${fnName}($params) {\n');
        buf.add('    $guard');
        if (isString) {
            buf.add('    static thread_local char _buf[4096];\n');
            buf.add('    _buf[0] = 0;\n');
        } else {
            buf.add('    $cReturnType _ret = $defaultReturn;\n');
        }
        buf.add('    {\n');
        buf.add('        HaxeBridgeScope _scope;\n');
        buf.add('        try {\n');
        if (isString) {
            buf.add('            ::String r = $call;\n');
            buf.add('            strncpy(_buf, r.__CStr(), sizeof(_buf) - 1);\n');
            buf.add('            _buf[sizeof(_buf) - 1] = 0;\n');
        } else {
            buf.add('            _ret = $call;\n');
        }
        buf.add('        } catch (::Dynamic _e) {\n');
        buf.add('            fprintf(stderr, "[sui] ${fnName}: Haxe exception\\n");\n');
        buf.add('        } catch (...) {\n');
        buf.add('            fprintf(stderr, "[sui] ${fnName}: C++ exception\\n");\n');
        buf.add('        }\n');
        buf.add('    }\n');
        if (isString) {
            buf.add('    return _buf;\n');
        } else {
            buf.add('    return _ret;\n');
        }
        buf.add('}\n\n');
    }

    static function generateBridgeSwift(appClassName:String, fns:Array<{name:String, params:Array<{name:String, swiftType:String}>, returnType:String}>, hasRuntimeActions:Bool):String {
        var buf = new StringBuf();
        buf.add("import Foundation\n\n");

        if (hasRuntimeActions) {
            // State callback: receives state updates from Haxe and dispatches to AppState
            buf.add("/// Called from C when Haxe State.set() is invoked.\n");
            buf.add("/// Updates AppState on the main thread so SwiftUI re-renders.\n");
            buf.add("func swiftStateCallback(_ key: UnsafePointer<CChar>?, _ value: UnsafePointer<CChar>?) {\n");
            buf.add("    let k = String(cString: key!)\n");
            buf.add("    let v = String(cString: value!)\n");
            buf.add("    DispatchQueue.main.async {\n");
            buf.add("        AppState.shared.set(k, v)\n");
            buf.add("    }\n");
            buf.add("}\n\n");
        }

        buf.add("/// Swift wrapper for Haxe bridge functions.\n");
        buf.add("enum HaxeBridgeC {\n");

        if (hasRuntimeActions) {
            buf.add("    /// Register the state callback. Called during HaxeRuntime.initialize().\n");
            buf.add("    static func registerCallbacks() {\n");
            buf.add("        haxe_bridge_register_state_callback(swiftStateCallback)\n");
            buf.add("    }\n\n");
            buf.add("    /// Invoke a button action registered in the Haxe view tree.\n");
            buf.add("    static func invokeAction(_ id: Int) {\n");
            buf.add("        haxe_bridge_invoke_action(Int32(id))\n");
            buf.add("    }\n\n");
        }
        // Shared-memory query wrappers — typed accessors
        buf.add("    // MARK: - Shared Memory Array Queries\n\n");
        buf.add("    static func arrayLength(_ stateName: String) -> Int {\n");
        buf.add("        return Int(haxe_bridge_array_length(stateName.cString(using: .utf8)))\n");
        buf.add("    }\n\n");
        buf.add("    static func arrayStringElement(_ stateName: String, at index: Int) -> String {\n");
        buf.add("        guard let cStr = haxe_bridge_array_string_element(stateName.cString(using: .utf8), Int32(index)) else { return \"\" }\n");
        buf.add("        return String(cString: cStr)\n");
        buf.add("    }\n\n");
        buf.add("    static func arrayIntElement(_ stateName: String, at index: Int) -> Int {\n");
        buf.add("        return Int(haxe_bridge_array_int_element(stateName.cString(using: .utf8), Int32(index)))\n");
        buf.add("    }\n\n");
        buf.add("    static func arrayFloatElement(_ stateName: String, at index: Int) -> Double {\n");
        buf.add("        return haxe_bridge_array_float_element(stateName.cString(using: .utf8), Int32(index))\n");
        buf.add("    }\n\n");
        buf.add("    static func arrayBoolElement(_ stateName: String, at index: Int) -> Bool {\n");
        buf.add("        return haxe_bridge_array_bool_element(stateName.cString(using: .utf8), Int32(index))\n");
        buf.add("    }\n\n");
        buf.add("    // MARK: - Shared Memory Object Field Queries\n\n");
        buf.add("    static func objectField(_ stateName: String, at index: Int, field: String) -> String {\n");
        buf.add("        guard let cStr = haxe_bridge_object_field(stateName.cString(using: .utf8), Int32(index), field.cString(using: .utf8)) else { return \"\" }\n");
        buf.add("        return String(cString: cStr)\n");
        buf.add("    }\n\n");
        buf.add("    static func objectIntField(_ stateName: String, at index: Int, field: String) -> Int {\n");
        buf.add("        return Int(haxe_bridge_object_int_field(stateName.cString(using: .utf8), Int32(index), field.cString(using: .utf8)))\n");
        buf.add("    }\n\n");
        buf.add("    static func objectFloatField(_ stateName: String, at index: Int, field: String) -> Double {\n");
        buf.add("        return haxe_bridge_object_float_field(stateName.cString(using: .utf8), Int32(index), field.cString(using: .utf8))\n");
        buf.add("    }\n\n");
        buf.add("    static func objectBoolField(_ stateName: String, at index: Int, field: String) -> Bool {\n");
        buf.add("        return haxe_bridge_object_bool_field(stateName.cString(using: .utf8), Int32(index), field.cString(using: .utf8))\n");
        buf.add("    }\n\n");

        for (fn in fns) {
            var swiftParams = [for (p in fn.params) '_ ${p.name}: ${p.swiftType}'];
            var retArrow = fn.returnType != "Void" ? ' -> ${fn.returnType}' : "";
            buf.add('    static func ${fn.name}(${swiftParams.join(", ")})${retArrow} {\n');

            // Call C function, casting Swift types to C types
            var cArgs:Array<String> = [];
            for (p in fn.params) {
                if (p.swiftType == "String")
                    cArgs.push('${p.name}.cString(using: .utf8)');
                else if (p.swiftType == "Int")
                    cArgs.push('Int32(${p.name})');
                else if (p.swiftType == "Double")
                    cArgs.push('Double(${p.name})');
                else
                    cArgs.push(p.name);
            }

            if (fn.returnType == "String") {
                buf.add('        let cStr = haxe_bridge_${fn.name}(${cArgs.join(", ")})\n');
                buf.add('        return String(cString: cStr!)\n');
            } else if (fn.returnType == "Int") {
                buf.add('        return Int(haxe_bridge_${fn.name}(${cArgs.join(", ")}))\n');
            } else if (fn.returnType != "Void") {
                buf.add('        return ${fn.returnType}(haxe_bridge_${fn.name}(${cArgs.join(", ")}))\n');
            } else {
                buf.add('        haxe_bridge_${fn.name}(${cArgs.join(", ")})\n');
            }
            buf.add("    }\n\n");
        }
        buf.add("}\n");
        return buf.toString();
    }

    /** Generate a Swift struct from an Observable subclass. **/
    static function generateModelStruct(cls:haxe.macro.Type.ClassType):String {
        var buf = new StringBuf();
        buf.add('struct ${cls.name}: Identifiable, Hashable {\n');
        buf.add('    let id = UUID()\n');

        for (field in cls.fields.get()) {
            // Skip inherited fields from Observable
            if (field.name.charAt(0) == "_") continue;
            if (field.name == "notifyPropertyChanged" || field.name == "consumeChanges") continue;

            var swiftType = haxeTypeToSwift(field.type);
            var defaultVal = swiftDefault(swiftType);
            buf.add('    var ${field.name}: ${swiftType} = ${defaultVal}\n');
        }

        buf.add("}\n");
        return buf.toString();
    }

    // ── Constructor walking ─────────────────────────────────────────

    static function walkCtor(expr:haxe.macro.Type.TypedExpr, stateDecls:Array<{name:String, swiftType:String, defaultValue:String}>, onAssign:(String, String) -> Void):Void {
        if (expr == null) return;
        switch (expr.expr) {
            case TFunction(f):
                walkCtor(f.expr, stateDecls, onAssign);
            case TBlock(el):
                for (e in el) walkCtor(e, stateDecls, onAssign);
            case TBinop(op, lhs, rhs):
                // Only handle OpAssign (index 4 in Binop enum)
                if (isOpAssign(op)) {
                    var fieldName = extractFieldName(lhs);
                    if (fieldName != null) {
                        // String assignment (appName = "...", bundleIdentifier = "...")
                        var strVal = extractString(rhs);
                        if (strVal != null) onAssign(fieldName, strVal);

                        // State init: field = new State<T>(value, "name")
                        switch (rhs.expr) {
                            case TNew(classRef, _, args):
                                if (classRef.get().name == "State" && args.length >= 1) {
                                    var initVal = extractConstant(args[0]);
                                    // Handle array literals: new State([])
                                    if (initVal == null) {
                                        var u = unwrap(args[0]);
                                        switch (u.expr) {
                                            case TArrayDecl(_): initVal = "[]";
                                            default:
                                        }
                                    }
                                    var stateName = if (args.length >= 2) extractString(args[1]) else null;
                                    for (sd in stateDecls) {
                                        if (sd.name == fieldName) {
                                            if (initVal != null) sd.defaultValue = initVal;
                                            if (stateName != null) sd.name = stateName;
                                        }
                                    }
                                }
                            default:
                        }
                    }
                }
            default:
        }
    }

    static function isOpAssign(op:haxe.macro.Expr.Binop):Bool {
        return switch (op) {
            case OpAssign: true;
            default: false;
        }
    }

    // ── View expression walking ─────────────────────────────────────

    // Variable bindings collected from TVar/TBlock so TLocal can be resolved
    static var localBindings:Map<Int, haxe.macro.Type.TypedExpr> = new Map();
    /** Tracks whether the current app needs the runtime bridge (has button closures). **/
    static var needsRuntimeBridge:Bool = false;
    /** Tracks whether the current app uses AdaptiveStack (needs @Environment horizontalSizeClass). **/
    static var needsHorizontalSizeClass:Bool = false;
    /** Counter for button action IDs (must match Button._nextActionId at runtime). **/
    static var nextActionId:Int = 0;

    static function walkFunc(expr:haxe.macro.Type.TypedExpr, indent:Int):String {
        if (expr == null) return "";
        switch (expr.expr) {
            case TFunction(f): return walkFunc(f.expr, indent);
            case TBlock(el):
                // Collect variable bindings, then process the return
                for (e in el) {
                    switch (e.expr) {
                        case TVar(v, initExpr):
                            if (initExpr != null)
                                localBindings.set(v.id, initExpr);
                        default:
                    }
                }
                if (el.length > 0) return walkFunc(el[el.length - 1], indent);
                return "";
            case TReturn(e): return if (e != null) viewToSwift(e, indent) else "";
            default:
                return viewToSwift(expr, indent);
        }
    }

    /** Walk `commands(): Array<CommandMenu>` — find the returned
        TArrayDecl, render each element via `viewToSwift`, and join
        with the right indentation for the `.commands { … }` block
        on the App's WindowGroup.

        Haxe's typer hoists complex sub-expressions into TVar
        bindings (e.g. inner `new Button(...)` references become
        TLocal pointing at synthesised vars). `viewToSwift` resolves
        TLocal through `localBindings`, so we walk the function body
        ahead of time and collect every TVar's init expression
        into that map. Without this pass the TLocal refs bubble up
        as `// [sui] unhandled expression: TLocal` placeholders. **/
    static function walkCommandsFunc(expr:haxe.macro.Type.TypedExpr):String {
        if (expr == null) return "";
        function collectBindings(e:haxe.macro.Type.TypedExpr):Void {
            if (e == null) return;
            switch (e.expr) {
                case TVar(v, initExpr):
                    if (initExpr != null) {
                        localBindings.set(v.id, initExpr);
                        collectBindings(initExpr);
                    }
                case TFunction(f): collectBindings(f.expr);
                case TBlock(stmts):
                    for (s in stmts) collectBindings(s);
                case TReturn(re): collectBindings(re);
                case TCast(inner, _): collectBindings(inner);
                case TParenthesis(inner): collectBindings(inner);
                case TMeta(_, inner): collectBindings(inner);
                case TArrayDecl(elems):
                    for (el in elems) collectBindings(el);
                case TNew(_, _, args):
                    for (a in args) collectBindings(a);
                case TCall(_, args):
                    for (a in args) collectBindings(a);
                case TArray(arr, idx):
                    collectBindings(arr);
                    collectBindings(idx);
                default:
            }
        }
        collectBindings(expr);

        // Descend through TFunction / TBlock / TReturn to the TArrayDecl.
        function findArrayDecl(e:haxe.macro.Type.TypedExpr):Null<Array<haxe.macro.Type.TypedExpr>> {
            if (e == null) return null;
            switch (e.expr) {
                case TFunction(f): return findArrayDecl(f.expr);
                case TBlock(stmts):
                    if (stmts.length > 0) return findArrayDecl(stmts[stmts.length - 1]);
                case TReturn(re): return findArrayDecl(re);
                case TCast(inner, _): return findArrayDecl(inner);
                case TParenthesis(inner): return findArrayDecl(inner);
                case TMeta(_, inner): return findArrayDecl(inner);
                case TArrayDecl(elems): return elems;
                default:
            }
            return null;
        }
        var elems = findArrayDecl(expr);
        if (elems == null || elems.length == 0) return "";
        var buf = new StringBuf();
        for (cm in elems) buf.add(viewToSwift(cm, 3));
        return buf.toString();
    }

    static function viewToSwift(expr:haxe.macro.Type.TypedExpr, indent:Int):String {
        // Unwrap casts, metas, parentheses
        var unwrapped = unwrap(expr);

        // Peel modifier chain (outside-in)
        var modifiers:Array<String> = [];
        var base = peelModifiers(unwrapped, modifiers, indent);

        // Generate base view
        var baseCode = baseToSwift(base, indent);

        if (modifiers.length == 0) return baseCode;

        // Append modifiers after base view
        // Replace __LIFECYCLE_ACTION__ placeholders with actual IDs
        // (assigned AFTER children, matching runtime registration order)
        var trimmed = baseCode.rtrim();
        var pad = ind(indent);
        var buf = new StringBuf();
        buf.add(trimmed);
        for (mod in modifiers) {
            var resolved = mod;
            while (resolved.indexOf("__LIFECYCLE_ACTION__") != -1) {
                var aid = nextActionId++;
                resolved = StringTools.replace(resolved, "__LIFECYCLE_ACTION__", Std.string(aid));
            }
            buf.add('\n${pad}    .$resolved');
        }
        buf.add("\n");
        return buf.toString();
    }

    static function unwrap(expr:haxe.macro.Type.TypedExpr):haxe.macro.Type.TypedExpr {
        return switch (expr.expr) {
            case TCast(e, _): unwrap(e);
            case TMeta(_, e): unwrap(e);
            case TParenthesis(e): unwrap(e);
            case TLocal(v):
                if (localBindings.exists(v.id))
                    unwrap(localBindings.get(v.id));
                else
                    expr;
            default: expr;
        }
    }

    static function peelModifiers(expr:haxe.macro.Type.TypedExpr, mods:Array<String>, indent:Int = 0):haxe.macro.Type.TypedExpr {
        var e = unwrap(expr);
        switch (e.expr) {
            case TCall(callee, args):
                var calU = unwrap(callee);
                switch (calU.expr) {
                    case TField(inner, fa):
                        var name = faName(fa);
                        if (isModifier(name)) {
                            mods.insert(0, modToSwift(name, args, indent));
                            return peelModifiers(inner, mods, indent);
                        }
                    default:
                }
            default:
        }
        return e;
    }

    static function baseToSwift(expr:haxe.macro.Type.TypedExpr, indent:Int):String {
        var pad = ind(indent);
        var e = unwrap(expr);
        switch (e.expr) {
            case TNew(classRef, _, args):
                return newToSwift(classRef.get(), args, indent);
            case TCall(callee, args):
                return factoryToSwift(unwrap(callee), args, indent);
            case TParenthesis(inner):
                return baseToSwift(inner, indent);
            default:
                Context.warning('[SwiftGen] Cannot generate Swift for expression: ${e.expr.getName()}. Use a literal, constructor, or factory method.', e.pos);
                return '${pad}// [sui] unhandled expression: ${e.expr.getName()}\n';
        }
    }

    // ── View constructors ───────────────────────────────────────────

    static function newToSwift(cls:haxe.macro.Type.ClassType, args:Array<haxe.macro.Type.TypedExpr>, indent:Int):String {
        var pad = ind(indent);
        var name = cls.name;
        switch (name) {
            case "VStack" | "HStack" | "ZStack" | "LazyVStack" | "LazyHStack":
                var spacing:String = null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        case TConst(c):
                            switch (c) {
                                case TFloat(v): spacing = v;
                                case TInt(v): spacing = Std.string(v);
                                default:
                            }
                        default:
                    }
                }
                var buf = new StringBuf();
                if (spacing != null)
                    buf.add('${pad}${name}(spacing: ${spacing}) {\n');
                else
                    buf.add('${pad}${name} {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "Text":
                if (args.length > 0) {
                    // Lambda item reference inside ForEach(state, item -> …):
                    // render as a string-interpolated Text so the live
                    // array element shows up.
                    var itemExpr = extractItemExpr(args[0]);
                    if (itemExpr != null) return '${pad}Text("\\(${itemExpr})")\n';
                    var text = extractString(args[0]);
                    if (text != null) return '${pad}Text("${esc(text)}")\n';
                    // Check for property reference: this.fieldName → emit as expression
                    var propName = extractThisField(args[0]);
                    if (propName != null) return '${pad}Text(${propName})\n';
                }
                return '${pad}Text("")\n';

            case "Button":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var actionCode:String = null;

                // Check for StateAction (args[2])
                if (args.length > 2) {
                    actionCode = stateActionToSwift(args[2]);
                }

                // If no StateAction, check if there's a runtime closure/function (args[1])
                if (actionCode == null && args.length > 1) {
                    var closureExpr = unwrap(args[1]);
                    switch (closureExpr.expr) {
                        case TConst(TNull):
                            // null — no action
                        default:
                            // Any non-null function reference (closure, method ref, local var)
                            // → invoke via bridge at runtime
                            var aid = nextActionId++;
                            needsRuntimeBridge = true;
                            actionCode = 'Task.detached { HaxeBridgeC.invokeAction($aid) }';
                    }
                }

                if (actionCode == null) actionCode = "// no action";

                var buf = new StringBuf();
                buf.add('${pad}Button("${esc(label != null ? label : "")}") {\n');
                buf.add('${pad}    ${actionCode}\n');
                buf.add('${pad}}\n');
                return buf.toString();

            case "NavigationLink":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var buf = new StringBuf();
                if (label != null && label.length > 0) {
                    buf.add('${pad}NavigationLink("${esc(label)}") {\n');
                    if (args.length > 1) buf.add(viewToSwift(args[1], indent + 1));
                    buf.add('${pad}}\n');
                } else {
                    // Custom label view: NavigationLink(destination:) { label }
                    buf.add('${pad}NavigationLink {\n');
                    if (args.length > 1) buf.add(viewToSwift(args[1], indent + 1));
                    buf.add('${pad}} label: {\n');
                    // labelView would be passed differently — handle basic case
                    buf.add('${pad}    Text("Link")\n');
                    buf.add('${pad}}\n');
                }
                return buf.toString();

            case "Rectangle": return '${pad}Rectangle()\n';
            case "Circle": return '${pad}Circle()\n';
            case "Capsule": return '${pad}Capsule()\n';
            case "Ellipse": return '${pad}Ellipse()\n';

            case "LinearGradient":
                // args[0] = TArrayDecl<ColorValue>, args[1] = startPoint String,
                // args[2] = endPoint String.
                var swiftColors = extractColorArrayToSwift(args.length > 0 ? args[0] : null);
                var start = args.length > 1 ? extractString(args[1]) : "top";
                var end = args.length > 2 ? extractString(args[2]) : "bottom";
                if (start == null) start = "top";
                if (end == null) end = "bottom";
                return '${pad}LinearGradient(colors: ${swiftColors}, startPoint: .${esc(start)}, endPoint: .${esc(end)})\n';

            case "RadialGradient":
                var swiftColors = extractColorArrayToSwift(args.length > 0 ? args[0] : null);
                var center = args.length > 1 ? extractString(args[1]) : "center";
                var startR = args.length > 2 ? extractConstant(args[2]) : "0";
                var endR = args.length > 3 ? extractConstant(args[3]) : "100";
                if (center == null) center = "center";
                if (startR == null) startR = "0";
                if (endR == null) endR = "100";
                return '${pad}RadialGradient(colors: ${swiftColors}, center: .${esc(center)}, startRadius: ${startR}, endRadius: ${endR})\n';

            case "AngularGradient":
                var swiftColors = extractColorArrayToSwift(args.length > 0 ? args[0] : null);
                var center = args.length > 1 ? extractString(args[1]) : "center";
                if (center == null) center = "center";
                return '${pad}AngularGradient(colors: ${swiftColors}, center: .${esc(center)})\n';

            case "Spacer":
                if (args.length > 0) {
                    var v = extractConstant(args[0]);
                    if (v != null) return '${pad}Spacer(minLength: ${v})\n';
                }
                return '${pad}Spacer()\n';

            case "NavigationStack":
                var buf = new StringBuf();
                buf.add('${pad}NavigationStack {\n');
                for (arg in args) {
                    switch (arg.expr) {
                        case TConst(TNull): // skip null args
                        default: buf.add(viewToSwift(arg, indent + 1));
                    }
                }
                buf.add('${pad}}\n');
                return buf.toString();

            case "List":
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    switch (arg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}List {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "DisclosureGroup":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                if (args.length > 1) {
                    var uArg = unwrap(args[1]);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}DisclosureGroup("${esc(label != null ? label : "")}") {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "GroupBox":
                var label = if (args.length > 0) extractString(args[0]) else null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                if (label != null)
                    buf.add('${pad}GroupBox("${esc(label)}") {\n');
                else
                    buf.add('${pad}GroupBox {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "LazyVGrid":
                var columns = if (args.length > 0) extractConstant(args[0]) else "2";
                var spacing:String = null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        case TConst(c):
                            switch (c) {
                                case TFloat(v): spacing = v;
                                case TInt(v): if (Std.string(v) != columns) spacing = Std.string(v);
                                default:
                            }
                        default:
                    }
                }
                var buf = new StringBuf();
                var cols = columns != null ? columns : "2";
                buf.add('${pad}LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: ${cols})');
                if (spacing != null) buf.add(', spacing: ${spacing}');
                buf.add(') {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "LazyHGrid":
                var rows = if (args.length > 0) extractConstant(args[0]) else "2";
                var spacing:String = null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        case TConst(c):
                            switch (c) {
                                case TFloat(v): spacing = v;
                                case TInt(v): if (Std.string(v) != rows) spacing = Std.string(v);
                                default:
                            }
                        default:
                    }
                }
                var buf = new StringBuf();
                var r = rows != null ? rows : "2";
                buf.add('${pad}LazyHGrid(rows: Array(repeating: GridItem(.flexible()), count: ${r})');
                if (spacing != null) buf.add(', spacing: ${spacing}');
                buf.add(') {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "ContentUnavailableView":
                var title = if (args.length > 0) extractString(args[0]) else "No Content";
                var sysImage = if (args.length > 1) extractString(args[1]) else null;
                var desc = if (args.length > 2) extractString(args[2]) else null;
                if (sysImage != null && desc != null)
                    return '${pad}ContentUnavailableView("${esc(title != null ? title : "")}", systemImage: "${esc(sysImage)}", description: Text("${esc(desc)}"))\n';
                else if (sysImage != null)
                    return '${pad}ContentUnavailableView("${esc(title != null ? title : "")}", systemImage: "${esc(sysImage)}")\n';
                else
                    return '${pad}ContentUnavailableView("${esc(title != null ? title : "")}", systemImage: "exclamationmark.triangle")\n';

            case "Gauge":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var binding = if (args.length > 1) extractString(args[1]) else "value";
                var rangeMin = if (args.length > 2) extractConstant(args[2]) else "0.0";
                var rangeMax = if (args.length > 3) extractConstant(args[3]) else "1.0";
                return '${pad}Gauge(value: ${binding}, in: ${rangeMin}...${rangeMax}) { Text("${esc(label != null ? label : "")}") }\n';

            case "ProgressView":
                var label = if (args.length > 0) extractString(args[0]) else null;
                var binding = if (args.length > 1) extractString(args[1]) else null;
                var total = if (args.length > 2) extractConstant(args[2]) else null;
                if (binding != null && total != null)
                    return '${pad}ProgressView("${esc(label != null ? label : "")}", value: ${binding}, total: ${total})\n';
                else if (label != null)
                    return '${pad}ProgressView("${esc(label)}")\n';
                else
                    return '${pad}ProgressView()\n';

            case "Stepper":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var binding = if (args.length > 1) extractString(args[1]) else "value";
                var rangeMin = if (args.length > 2) extractConstant(args[2]) else "0";
                var rangeMax = if (args.length > 3) extractConstant(args[3]) else "100";
                return '${pad}Stepper("${esc(label != null ? label : "")}", value: $$${binding}, in: ${rangeMin}...${rangeMax})\n';

            case "Link":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var url = if (args.length > 1) extractString(args[1]) else "";
                return '${pad}Link("${esc(label != null ? label : "")}", destination: URL(string: "${esc(url != null ? url : "")}")!)\n';

            case "ShareLink":
                // args[0]: item (String). args[1]: optional label
                // String — without it, SwiftUI shows the default
                // share-arrow icon.
                var item = if (args.length > 0) extractString(args[0]) else "";
                var label = if (args.length > 1) extractString(args[1]) else null;
                if (label != null && label != "")
                    return '${pad}ShareLink(item: "${esc(item != null ? item : "")}") {\n${pad}    Text("${esc(label)}")\n${pad}}\n';
                else
                    return '${pad}ShareLink(item: "${esc(item != null ? item : "")}")\n';

            case "Image":
                if (args.length > 0) {
                    var n = extractString(args[0]);
                    return '${pad}Image("${esc(n != null ? n : "")}")\n';
                }
                return '${pad}Image("")\n';

            case "Picker":
                var label = if (args.length > 0) extractString(args[0]) else "";
                var binding = if (args.length > 1) extractString(args[1]) else "selection";
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                if (args.length > 2) {
                    var uArg = unwrap(args[2]);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}Picker("${esc(label != null ? label : "")}", selection: $$${binding}) {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "Slider":
                var binding = if (args.length > 0) extractString(args[0]) else "value";
                var rangeMin = if (args.length > 1) extractConstant(args[1]) else "0";
                var rangeMax = if (args.length > 2) extractConstant(args[2]) else "1";
                return '${pad}Slider(value: $$${binding}, in: ${rangeMin}...${rangeMax})\n';

            case "ScrollView":
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        case TConst(TNull):
                        default: children.push(arg);
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}ScrollView {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "Form":
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}Form {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "ForEach":
                return forEachToSwift(args, indent);

            case "TabView":
                return tabViewToSwift(args, indent);

            case "NavigationSplitView":
                // args[0] = sidebar, args[1] = detail
                var buf = new StringBuf();
                buf.add('${pad}NavigationSplitView {\n');
                if (args.length > 0) buf.add(viewToSwift(args[0], indent + 1));
                buf.add('${pad}} detail: {\n');
                if (args.length > 1) buf.add(viewToSwift(args[1], indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "ConditionalView":
                // args: stateName, trueView, falseView (optional)
                // or: stateName, matchValue (string), matchView, elseView (optional)
                var stateName = if (args.length > 0) resolveStateName(args[0]) else "condition";
                var buf = new StringBuf();

                // Detect string equality mode: 4 args where arg[1] is a string constant (not a view)
                var isStringMatch = false;
                if (args.length >= 3) {
                    var maybeStr = extractString(args[1]);
                    // Check if arg[1] is a plain string constant (not a view constructor)
                    if (maybeStr != null) {
                        var u1 = unwrap(args[1]);
                        switch (u1.expr) {
                            case TConst(TString(_)): isStringMatch = true;
                            default:
                        }
                    }
                }

                if (isStringMatch) {
                    var matchVal = extractString(args[1]);
                    buf.add('${pad}if ${stateName} == "${esc(matchVal)}" {\n');
                    buf.add(viewToSwift(args[2], indent + 1));
                    buf.add('${pad}}');
                    if (args.length > 3) {
                        var uElse = unwrap(args[3]);
                        switch (uElse.expr) {
                            case TConst(TNull):
                            default:
                                buf.add(' else {\n');
                                buf.add(viewToSwift(args[3], indent + 1));
                                buf.add('${pad}}');
                        }
                    }
                    buf.add('\n');
                } else {
                    buf.add('${pad}if ${stateName} {\n');
                    if (args.length > 1) buf.add(viewToSwift(args[1], indent + 1));
                    buf.add('${pad}}');
                    if (args.length > 2) {
                        var uElse = unwrap(args[2]);
                        switch (uElse.expr) {
                            case TConst(TNull):
                            default:
                                buf.add(' else {\n');
                                buf.add(viewToSwift(args[2], indent + 1));
                                buf.add('${pad}}');
                        }
                    }
                    buf.add('\n');
                }
                return buf.toString();

            case "Section":
                var header:String = null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                for (arg in args) {
                    var uArg = unwrap(arg);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        case TConst(TString(s)): header = s;
                        case TConst(TNull):
                        default:
                            // Could be a string header
                            var s = extractString(uArg);
                            if (s != null) header = s;
                    }
                }
                var buf = new StringBuf();
                if (header != null)
                    buf.add('${pad}Section("${esc(header)}") {\n');
                else
                    buf.add('${pad}Section {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "Menu":
                // First arg is the label (String), second is a
                // TArrayDecl of child views (typically Buttons or
                // nested Menus).
                var label = if (args.length > 0) extractString(args[0]) else null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                if (args.length > 1) {
                    var uArg = unwrap(args[1]);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}Menu("${esc(label != null ? label : "")}") {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "CommandMenu":
                // Top-level macOS menu-bar menu. Same shape as
                // `Section` / `Menu`: label string + TArrayDecl of
                // children. Attached to the App scene by the App.swift
                // emitter via `.commands { … }`.
                var label = if (args.length > 0) extractString(args[0]) else null;
                var children:Array<haxe.macro.Type.TypedExpr> = [];
                if (args.length > 1) {
                    var uArg = unwrap(args[1]);
                    switch (uArg.expr) {
                        case TArrayDecl(el): children = el;
                        default:
                    }
                }
                var buf = new StringBuf();
                buf.add('${pad}CommandMenu("${esc(label != null ? label : "")}") {\n');
                for (child in children)
                    buf.add(viewToSwift(child, indent + 1));
                buf.add('${pad}}\n');
                return buf.toString();

            case "AdaptiveStack":
                needsHorizontalSizeClass = true;
                var buf = new StringBuf();
                buf.add('${pad}if horizontalSizeClass == .regular {\n');
                buf.add('${pad}    NavigationSplitView {\n');
                if (args.length > 0) buf.add(viewToSwift(args[0], indent + 2));
                buf.add('${pad}    } detail: {\n');
                if (args.length > 1) buf.add(viewToSwift(args[1], indent + 2));
                buf.add('${pad}    }\n');
                buf.add('${pad}} else {\n');
                buf.add('${pad}    NavigationStack {\n');
                buf.add('${pad}        VStack {\n');
                if (args.length > 0) buf.add(viewToSwift(args[0], indent + 3));
                if (args.length > 1) buf.add(viewToSwift(args[1], indent + 3));
                buf.add('${pad}        }\n');
                buf.add('${pad}    }\n');
                buf.add('${pad}}\n');
                return buf.toString();

            default:
                // Generic: read @:swiftView, @:swiftLabel, @:swiftBinding metadata
                return genericViewToSwift(cls, args, indent);
        }
    }

    /** Generic view generation using @:swiftView, @:swiftLabel, @:swiftBinding metadata. **/
    static function genericViewToSwift(cls:haxe.macro.Type.ClassType, args:Array<haxe.macro.Type.TypedExpr>, indent:Int):String {
        var pad = ind(indent);
        var swiftName = getMetaString(cls.meta, ":swiftView");
        if (swiftName == null) swiftName = cls.name;

        // Read constructor parameter metadata
        if (cls.constructor != null) {
            var ctor = cls.constructor.get();
            var paramInfo = getParamInfo(ctor);
            var swiftArgs:Array<String> = [];

            for (i in 0...args.length) {
                if (i >= paramInfo.length) break;
                var info = paramInfo[i];
                var argVal = resolveArgValue(args[i], info.isBinding);
                if (argVal == null) continue; // skip null optionals

                if (info.label == "_") {
                    swiftArgs.push(argVal);
                } else if (info.label != null) {
                    swiftArgs.push('${info.label}: $argVal');
                } else {
                    swiftArgs.push(argVal);
                }
            }
            return '${pad}${swiftName}(${swiftArgs.join(", ")})\n';
        }

        return '${pad}// [sui] Unknown view: ${cls.name} — add @:swiftView metadata or a constructor\n';
    }

    /** Resolve an argument to its Swift string value, handling bindings. **/
    static function resolveArgValue(expr:haxe.macro.Type.TypedExpr, isBinding:Bool):String {
        var e = unwrap(expr);
        switch (e.expr) {
            case TConst(TNull): return null;
            default:
        }
        var str = extractString(e);
        if (str != null) {
            if (isBinding) return '$$$str'; // emit $varName
            return '"${esc(str)}"';
        }
        // For binding params, try to extract the field name from a state reference.
        // This handles both direct field refs (this.name) and @:from abstract
        // conversions (TextInputBinding.fromState(this.name)).
        if (isBinding) {
            var fieldName = extractBindingFieldName(e);
            if (fieldName != null) return '$$$fieldName';
        }
        var c = extractConstant(e);
        return c;
    }

    /** Extract a field name from a state field reference, unwrapping through
        abstract @:from calls, casts, and property chains like this.field.name.
        Returns the name of the field on `this` (the App class). **/
    static function extractBindingFieldName(expr:haxe.macro.Type.TypedExpr):String {
        var e = unwrap(expr);
        switch (e.expr) {
            case TField(obj, FInstance(_, _, fieldRef)):
                // If this field is directly on `this`, return its name
                var uObj = unwrap(obj);
                switch (uObj.expr) {
                    case TConst(TThis):
                        return fieldRef.get().name;
                    case TField(_, _):
                        // Chain like this.newsletter.name — recurse on inner object
                        return extractBindingFieldName(obj);
                    default:
                }
            case TField(_, FStatic(_, fieldRef)):
                return fieldRef.get().name;
            case TCall(_, args):
                // Unwrap through @:from conversion calls
                if (args.length > 0) return extractBindingFieldName(args[0]);
            case TNew(_, _, args):
                // Unwrap through abstract constructor calls
                if (args.length > 0) return extractBindingFieldName(args[0]);
            case TCast(inner, _):
                return extractBindingFieldName(inner);
            default:
        }
        return null;
    }

    // ── ForEach ─────────────────────────────────────────────────────

    /**
        ForEach constructor: new ForEach(arrayName, itemName, childView)
        Generates: ForEach(0..<arrayName.count, id: \.self) { itemName in childView }
    **/
    static function forEachToSwift(args:Array<haxe.macro.Type.TypedExpr>, indent:Int):String {
        var pad = ind(indent);
        // Two call shapes:
        //   * legacy 3-arg: (arrayName, itemVarName, childView) — keep working
        //   * lambda 2-arg: (arrayName, item -> childView) — closure form
        //     where `item` references inside the body resolve to the
        //     per-iteration element via `currentItemBinding`. Modifiers
        //     and Text codegen check the binding before falling back to
        //     constant-string extraction.
        var arrayName = if (args.length > 0) resolveStateName(args[0]) else "items";

        var lambda = (args.length >= 2) ? unwrapLambda(args[1]) : null;
        if (lambda != null) {
            var itemName = lambda.paramName != null && lambda.paramName != "" ? lambda.paramName : "item";
            var prev = currentItemBinding;
            // Closure form: iterate directly over the array's elements
            // so the Haxe-typed lambda parameter and the Swift binding
            // refer to the same value (`color: String`, not the index).
            // SwiftUI's `ForEach(_:id:_:)` requires the element type to
            // be Hashable — `id: \.self` is the standard escape hatch.
            currentItemBinding = {
                paramId: lambda.paramId,
                swiftExpr: itemName,
            };
            var buf = new StringBuf();
            buf.add('${pad}ForEach(${arrayName}, id: \\.self) { ${itemName} in\n');
            buf.add(viewToSwift(lambda.body, indent + 1));
            buf.add('${pad}}\n');
            currentItemBinding = prev;
            return buf.toString();
        }

        // Legacy form
        var itemName = if (args.length > 1) extractString(args[1]) else "item";
        var buf = new StringBuf();
        buf.add('${pad}ForEach(0..<${arrayName}.count, id: \\.self) { ${itemName} in\n');
        if (args.length > 2) {
            buf.add(viewToSwift(args[2], indent + 1));
        }
        buf.add('${pad}}\n');
        return buf.toString();
    }

    /** State tracking for the closure form of ForEach: when the macro
        is mid-traversal of a lambda body, this points to the iteration
        parameter and the matching Swift expression. **/
    static var currentItemBinding:Null<{paramId:Int, swiftExpr:String}> = null;

    /** Unwrap (cast/paren/etc.) and check if the expression is a
        unary-arg lambda — used by the closure form of ForEach. The
        lambda body is also unwrapped: arrow-syntax bodies arrive as a
        TBlock wrapping a single TReturn, which would otherwise fall
        through `viewToSwift` and emit "unhandled expression: TBlock". **/
    static function unwrapLambda(expr:haxe.macro.Type.TypedExpr):Null<{paramId:Int, paramName:String, body:haxe.macro.Type.TypedExpr}> {
        if (expr == null) return null;
        var e = unwrap(expr);
        return switch (e.expr) {
            case TFunction(fn):
                if (fn.args.length != 1) null;
                else {
                    paramId: fn.args[0].v.id,
                    paramName: fn.args[0].v.name,
                    body: unwrapLambdaBody(fn.expr),
                };
            default: null;
        }
    }

    /** Peel TBlock/TReturn/TMeta layers Haxe adds around the actual
        expression returned by an arrow-syntax lambda. **/
    static function unwrapLambdaBody(expr:haxe.macro.Type.TypedExpr):haxe.macro.Type.TypedExpr {
        if (expr == null) return expr;
        return switch (expr.expr) {
            case TBlock(stmts):
                // Single-stmt blocks are the common shape (the typer
                // wraps `arg -> expr` into `function(arg){ return expr; }`),
                // but the typer also synthesizes intermediate locals
                // for sub-expressions when the body references types
                // it can't inline — e.g. `arr.value[i]` for a Haxe
                // property — landing here as multi-statement blocks
                // of TVar declarations followed by a final TReturn.
                // Register the TVars in `localBindings` so the rest
                // of the view-tree pass can dereference them, then
                // unwrap the final TReturn.
                if (stmts.length == 0) expr;
                else if (stmts.length == 1) unwrapLambdaBody(stmts[0]);
                else {
                    for (s in stmts) {
                        switch (s.expr) {
                            case TVar(v, initExpr) if (initExpr != null):
                                localBindings.set(v.id, initExpr);
                            default:
                        }
                    }
                    var last = stmts[stmts.length - 1];
                    switch (last.expr) {
                        case TReturn(_): unwrapLambdaBody(last);
                        default: expr;
                    }
                }
            case TReturn(e):
                e != null ? unwrapLambdaBody(e) : expr;
            case TMeta(_, e): unwrapLambdaBody(e);
            case TParenthesis(e): unwrapLambdaBody(e);
            case TCast(e, _): unwrapLambdaBody(e);
            default: expr;
        }
    }

    /** Return the Swift expression for the currently-bound lambda
        item if the given typed expression is a reference to it.
        Used by modifier codegens that want to accept either a literal
        string or a typed item reference.

        Recognises two shapes:
          1. **Bare lambda param** (`item`) — the closure parameter
             itself. Resolves to `currentItemBinding.swiftExpr`.
          2. **Indexed parallel-array access** (`other.value[item]`,
             where `other` is a `State<Array<T>>` field and `item` is
             the closure param). Resolves to
             `appState.<other-state-name>[<swiftExpr>]`, so a
             closure-form ForEach iterating one array can subscript
             any number of parallel arrays by typed Haxe code instead
             of stringly `"otherArrayName[i]"` patterns. **/
    static function extractItemExpr(expr:haxe.macro.Type.TypedExpr):Null<String> {
        if (currentItemBinding == null || expr == null) return null;
        var e = unwrap(expr);
        switch (e.expr) {
            case TLocal(v):
                return v.id == currentItemBinding.paramId
                    ? currentItemBinding.swiftExpr
                    : null;
            case TArray(arr, idx):
                // Check whether the index is the bound lambda param.
                var idxU = unwrap(idx);
                var idxRef = switch (idxU.expr) {
                    case TLocal(v) if (v.id == currentItemBinding.paramId):
                        currentItemBinding.swiftExpr;
                    default: null;
                };
                if (idxRef == null) return null;
                // Resolve the array's underlying state-field name.
                // `state.value` shows up as either a direct TField
                // (Haxe property) or as a TCall to its getter.
                var stateName = resolveValueAccessStateName(arr);
                if (stateName == null) return null;
                return '${stateName}[${idxRef}]';
            default:
                return null;
        }
    }

    /** Walk `someState.value` (or its getter form) and recover the
        receiver's state-field name. Returns null for anything that
        doesn't look like a `.value` access on a State<T> field. **/
    static function resolveValueAccessStateName(expr:haxe.macro.Type.TypedExpr):Null<String> {
        if (expr == null) return null;
        var e = unwrap(expr);
        switch (e.expr) {
            case TField(receiver, _):
                return resolveStateName(receiver);
            case TCall(callee, _):
                var calU = unwrap(callee);
                switch (calU.expr) {
                    case TField(receiver, _):
                        return resolveStateName(receiver);
                    default:
                }
            default:
        }
        return null;
    }

    /**
        TabView: args is an array of TabItem objects (created via TNew or TObjectDecl).
        Each TabItem has {label, systemImage, content}.
        The macro walks the constructor args to extract the tab items array.
    **/
    static function tabViewToSwift(args:Array<haxe.macro.Type.TypedExpr>, indent:Int):String {
        var pad = ind(indent);
        var buf = new StringBuf();
        buf.add('${pad}TabView {\n');

        // args[0] should be an array of TabItem structs
        if (args.length > 0) {
            var uArg = unwrap(args[0]);
            switch (uArg.expr) {
                case TArrayDecl(items):
                    for (item in items) {
                        var uItem = unwrap(item);
                        // TabItem is constructed as an anonymous object or via fields
                        var label = "";
                        var sysImg = "";
                        var contentExpr:haxe.macro.Type.TypedExpr = null;

                        switch (uItem.expr) {
                            case TObjectDecl(fields):
                                for (f in fields) {
                                    switch (f.name) {
                                        case "label": label = extractString(f.expr) ?? "";
                                        case "systemImage": sysImg = extractString(f.expr) ?? "";
                                        case "content": contentExpr = f.expr;
                                    }
                                }
                            default:
                        }

                        if (contentExpr != null) {
                            buf.add(viewToSwift(contentExpr, indent + 1));
                            // Remove trailing newline, add tabItem modifier
                            var code = buf.toString();
                            if (code.endsWith("\n")) {
                                buf = new StringBuf();
                                buf.add(code.substr(0, code.length - 1));
                            }
                            buf.add('\n${pad}        .tabItem { Label("${esc(label)}", systemImage: "${esc(sysImg)}") }\n');
                        }
                    }
                default:
            }
        }

        buf.add('${pad}}\n');
        return buf.toString();
    }

    // ── Static factory calls ────────────────────────────────────────
    // Reads @:swiftName on the method and @:swiftLabel on parameters
    // to generically emit any Swift call without hardcoding.
    // Special case: Text.withState uses template interpolation.

    /** Check if a field's return type is View or a View subclass. **/
    static function returnsView(field:haxe.macro.Type.ClassField):Bool {
        switch (field.type) {
            case TFun(_, ret):
                switch (ret) {
                    case TInst(ref, _):
                        var cls = ref.get();
                        if (cls.name == "View" && cls.pack.join(".") == "sui") return true;
                        // Check superclass chain for View
                        var sc = cls.superClass;
                        while (sc != null) {
                            var scCls = sc.t.get();
                            if (scCls.name == "View" && scCls.pack.join(".") == "sui") return true;
                            sc = scCls.superClass;
                        }
                    default:
                }
            default:
        }
        return false;
    }

    /** Try to inline a view-returning function call. Returns null if not resolvable. **/
    static function tryInlineViewCall(field:haxe.macro.Type.ClassField, args:Array<haxe.macro.Type.TypedExpr>, indent:Int):String {
        if (!returnsView(field)) return null;
        // Static factories that carry @:swiftName have their own Swift
        // emission (`generateSwiftCall` reads :swiftLabel-tagged params
        // and builds the matching initializer call) — inlining them
        // would walk the Haxe body and ignore those annotations,
        // emitting whatever stub the factory uses internally. The
        // canonical case is `Image.systemImage(...)` whose body builds
        // `new Image("")` as a placeholder, so without this guard the
        // generated Swift came out as `Image("")` instead of
        // `Image(systemName: "...")`.
        if (getMetaString(field.meta, ":swiftName") != null) return null;
        var funcExpr = field.expr();
        if (funcExpr == null) return null;

        // Map call arguments to function parameter IDs in localBindings
        switch (funcExpr.expr) {
            case TFunction(f):
                for (i in 0...f.args.length) {
                    if (i < args.length) {
                        localBindings.set(f.args[i].v.id, args[i]);
                    }
                }
            default:
        }

        return walkFunc(funcExpr, indent);
    }

    static function factoryToSwift(callee:haxe.macro.Type.TypedExpr, args:Array<haxe.macro.Type.TypedExpr>, indent:Int):String {
        var pad = ind(indent);
        switch (callee.expr) {
            case TField(_, fa):
                switch (fa) {
                    case FStatic(classRef, fieldRef):
                        var cls = classRef.get();
                        var field = fieldRef.get();

                        // Special case: Text.withState uses {var} → \(var) interpolation
                        if (cls.name == "Text" && field.name == "withState" && args.length > 0) {
                            var template = extractString(args[0]);
                            if (template != null)
                                return '${pad}Text(${templateToSwift(template)})\n';
                        }

                        // Try inlining view-returning function calls
                        var inlined = tryInlineViewCall(field, args, indent);
                        if (inlined != null) return inlined;

                        // Generic: read @:swiftName and @:swiftLabel metadata
                        var swiftName = getMetaString(field.meta, ":swiftName");
                        if (swiftName != null) {
                            return generateSwiftCall(swiftName, field, args, pad);
                        }

                        // Fallback: use Haxe class name + labeled args from metadata
                        return generateSwiftCall(cls.name, field, args, pad);

                    case FInstance(_, _, fieldRef):
                        var field = fieldRef.get();

                        // Try inlining view-returning instance method calls
                        var inlined = tryInlineViewCall(field, args, indent);
                        if (inlined != null) return inlined;

                    default:
                }
            default:
        }
        Context.warning('[SwiftGen] Cannot generate Swift for this factory call. Add @:swiftName metadata to the method.', callee.pos);
        return '${pad}// [sui] unhandled factory call — add @:swiftName metadata\n';
    }

    /** Generate a Swift function/initializer call using @:swiftLabel/@:swiftBinding metadata. **/
    static function generateSwiftCall(swiftName:String, field:haxe.macro.Type.ClassField, args:Array<haxe.macro.Type.TypedExpr>, pad:String):String {
        var params = getParamInfo(field);
        var swiftArgs:Array<String> = [];

        for (i in 0...args.length) {
            if (i >= params.length) break;
            var info = params[i];
            var argVal = resolveArgValue(args[i], info.isBinding);
            if (argVal == null) continue;

            if (info.label == "_") {
                swiftArgs.push(argVal);
            } else if (info.label != null) {
                swiftArgs.push('${info.label}: $argVal');
            } else {
                swiftArgs.push(argVal);
            }
        }

        return '${pad}${swiftName}(${swiftArgs.join(", ")})\n';
    }

    /** Read @:swiftLabel and @:swiftBinding metadata from parameters. **/
    static function getParamInfo(field:haxe.macro.Type.ClassField):Array<{label:Null<String>, isBinding:Bool}> {
        var info:Array<{label:Null<String>, isBinding:Bool}> = [];

        switch (field.type) {
            case TFun(fnArgs, _):
                for (_ in fnArgs)
                    info.push({label: null, isBinding: false});
            default:
                return info;
        }

        var expr = field.expr();
        if (expr != null) {
            switch (expr.expr) {
                case TFunction(f):
                    for (i in 0...f.args.length) {
                        if (i >= info.length) break;
                        var v = f.args[i].v;
                        if (v.meta != null) {
                            var label = getMetaString(v.meta, ":swiftLabel");
                            if (label != null) info[i].label = label;
                            if (v.meta.has(":swiftBinding")) info[i].isBinding = true;
                        }
                    }
                default:
            }
        }
        return info;
    }

    /** Extract a string value from a metadata entry like @:swiftName("Foo"). **/
    static function getMetaString(meta:haxe.macro.Type.MetaAccess, name:String):String {
        if (meta == null || !meta.has(name)) return null;
        var entries = meta.extract(name);
        if (entries.length > 0 && entries[0].params != null && entries[0].params.length > 0) {
            switch (entries[0].params[0].expr) {
                case EConst(c):
                    switch (c) {
                        case CString(s, _): return s;
                        default:
                    }
                default:
            }
        }
        return null;
    }

    // ── State actions ───────────────────────────────────────────────

    /** Resolve a StateAction state reference: accepts State<T> field refs or string names. **/
    static function resolveStateName(expr:haxe.macro.Type.TypedExpr):String {
        if (expr == null) return null;
        // Try as string first (backward compat)
        var s = extractString(expr);
        if (s != null) return s;
        // Try as State<T> field reference
        var e = unwrap(expr);
        switch (e.expr) {
            case TField(_, fa):
                switch (fa) {
                    case FInstance(_, _, fieldRef): return fieldRef.get().name;
                    case FStatic(_, fieldRef): return fieldRef.get().name;
                    default:
                }
            default:
                var fieldName = extractThisField(e);
                if (fieldName != null) return fieldName;
        }
        return null;
    }

    /** Convert an AnimationCurve enum value to a Swift animation name. **/
    static function resolveAnimationCurve(expr:haxe.macro.Type.TypedExpr):String {
        var e = unwrap(expr);
        // Handle enum value
        var name = extractEnumName(e);
        if (name != null) return camel(name);
        // Fallback to string
        var s = extractString(e);
        return s != null ? s : "default";
    }

    static function stateActionToSwift(expr:haxe.macro.Type.TypedExpr):String {
        var e = unwrap(expr);
        switch (e.expr) {
            case TCall(callee, args):
                switch (callee.expr) {
                    case TField(_, fa):
                        switch (fa) {
                            case FEnum(_, ef):
                                var p0 = if (args.length > 0) resolveStateName(args[0]) else null;
                                var p1 = if (args.length > 1) extractConstant(args[1]) else null;
                                return switch (ef.name) {
                                    case "Increment": '${p0} += ${p1 != null ? p1 : "1"}';
                                    case "Decrement": '${p0} -= ${p1 != null ? p1 : "1"}';
                                    case "SetValue": '${p0} = ${p1 != null ? p1 : "0"}';
                                    case "Toggle": '${p0}.toggle()';
                                    case "CustomSwift":
                                        var code = if (args.length > 0) extractString(args[0]) else null;
                                        code != null ? code : "// custom";
                                    case "BridgeCall":
                                        var fnName = if (args.length > 1) extractString(args[1]) else "unknown";
                                        var argStr = if (args.length > 2) extractBridgeArgs(args[2]) else "";
                                        'Task.detached { let r = HaxeBridgeC.${fnName}(${argStr}); await MainActor.run { ${p0} = r } }';
                                    case "BridgeCallLoading":
                                        var loadingVal = if (args.length > 1) extractString(args[1]) else "Loading...";
                                        var fnName = if (args.length > 2) extractString(args[2]) else "unknown";
                                        var argStr = if (args.length > 3) extractBridgeArgs(args[3]) else "";
                                        '${p0} = "${esc(loadingVal)}"; Task.detached { let r = HaxeBridgeC.${fnName}(${argStr}); await MainActor.run { ${p0} = r } }';
                                    case "Animated":
                                        var innerAction = if (args.length > 0) stateActionToSwift(args[0]) else null;
                                        var curve = if (args.length > 1) resolveAnimationCurve(args[1]) else "default";
                                        if (innerAction != null)
                                            'withAnimation(.${curve}) { ${innerAction} }';
                                        else
                                            null;
                                    default: null;
                                }
                            default:
                        }
                    default:
                }
            case TConst(TNull):
                return null;
            default:
        }
        return null;
    }

    // ── Modifiers ───────────────────────────────────────────────────

    static function isModifier(name:String):Bool {
        return switch (name) {
            case "padding" | "font" | "foregroundColor" | "background" | "backgroundMaterial" |
                 "foregroundHex" | "backgroundHex" | "bold" | "italic" |
                 "frame" | "fillWidth" | "fillHeight" | "fillBoth" | "fixedSize" |
                 "cornerRadius" | "opacity" | "navigationTitle" | "multilineTextAlignment" |
                 "disabled" | "overlay" | "shadow" | "lineLimit" | "textFieldStyle" |
                 "buttonStyle" | "toggleStyle" | "pickerStyle" | "scrollIndicators" |
                 "sheet" | "inspector" | "inspectorColumnWidth" | "alert" | "confirmationDialog" | "searchable" | "toolbar" | "animation" |
                 "onAppear" | "onDisappear" | "task" | "navigationDestination" |
                 "onTapGesture" | "tint" | "badge" | "tag" |
                 "onAppearAction" | "taskAction" | "toolbarItem" |
                 "blur" | "scaleEffect" | "rotationEffect" | "offset" |
                 "brightness" | "contrast" | "saturation" | "grayscale" |
                 "fullScreenCover" | "popover" | "contextMenu" | "swipeActions" | "refreshable" |
                 "listStyle" | "aspectRatio" | "accessibilityLabel" | "help" |
                 "onSubmit" | "onLongPressGesture" | "transition" |
                 "onChange" | "keyboardShortcut" | "onKeyPress":
                true;
            default: false;
        }
    }

    static function modToSwift(name:String, args:Array<haxe.macro.Type.TypedExpr>, indent:Int = 0):String {
        return switch (name) {
            case "padding":
                var v = if (args.length > 0) extractConstant(args[0]) else null;
                v != null ? 'padding(${v})' : "padding()";
            case "font":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'font(.${e != null ? camel(e) : "body"})';
            case "foregroundColor":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'foregroundStyle(${colorEnumToSwift(e, "primary")})';
            case "background":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'background(${colorEnumToSwift(e, "clear")})';
            case "foregroundHex":
                // Closure-form ForEach typed item refs and indexed
                // accesses (`item`, `other.value[i]`) take priority;
                // legacy string-name args fall through to the verbatim
                // embed + appState-prefix pass.
                'foregroundStyle(Color(suiHex: ${resolveHexExpr(args)}) ?? Color.primary)';
            case "backgroundHex":
                'background(Color(suiHex: ${resolveHexExpr(args)}) ?? Color.clear)';
            case "backgroundMaterial":
                // MaterialStyle enum → SwiftUI Material constant.
                // Regular → .regularMaterial, Bar → .bar, etc.
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                var swift = if (e == "Bar") ".bar"
                    else if (e == null) ".regularMaterial"
                    else '.${camel(e)}Material';
                'background(${swift})';
            case "bold": "bold()";
            case "italic": "italic()";
            case "opacity":
                var v = if (args.length > 0) extractConstant(args[0]) else "1.0";
                'opacity(${v})';
            case "navigationTitle":
                var s = if (args.length > 0) extractString(args[0]) else "";
                'navigationTitle("${esc(s != null ? s : "")}")';
            case "cornerRadius":
                var v = if (args.length > 0) extractConstant(args[0]) else "0";
                'clipShape(RoundedRectangle(cornerRadius: ${v}))';
            case "frame":
                var parts:Array<String> = [];
                if (args.length > 0) { var w = extractConstant(args[0]); if (w != null) parts.push('width: $w'); }
                if (args.length > 1) { var h = extractConstant(args[1]); if (h != null) parts.push('height: $h'); }
                'frame(${parts.join(", ")})';
            // Stretch helpers — workarounds for SwiftUI containers that
            // collapse to zero in layout contexts without a definite
            // intrinsic size (notably `List` inside `.sheet` content).
            case "fillWidth":
                'frame(maxWidth: .infinity)';
            case "fillHeight":
                'frame(maxHeight: .infinity)';
            case "fillBoth":
                'frame(maxWidth: .infinity, maxHeight: .infinity)';
            case "fixedSize":
                // Defaults match Haxe-side: horizontal=false, vertical=true.
                var h = if (args.length > 0) extractConstant(args[0]) else "false";
                var v = if (args.length > 1) extractConstant(args[1]) else "true";
                if (h == null) h = "false";
                if (v == null) v = "true";
                'fixedSize(horizontal: $h, vertical: $v)';
            case "disabled":
                var v = if (args.length > 0) extractConstant(args[0]) else "true";
                'disabled($v)';
            case "lineLimit":
                var v = if (args.length > 0) extractConstant(args[0]) else "1";
                'lineLimit($v)';
            case "shadow":
                var parts:Array<String> = [];
                if (args.length > 0) { var e = extractEnumName(args[0]); if (e != null) parts.push('color: ${colorEnumToSwift(e, "primary")}'); }
                if (args.length > 1) { var r = extractConstant(args[1]); if (r != null) parts.push('radius: $r'); }
                'shadow(${parts.join(", ")})';
            case "textFieldStyle":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'textFieldStyle(.${e != null ? camel(e) : "automatic"})';
            case "buttonStyle":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'buttonStyle(.${e != null ? camel(e) : "automatic"})';
            case "toggleStyle":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'toggleStyle(.${e != null ? camel(e) : "automatic"})';
            case "pickerStyle":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'pickerStyle(.${e != null ? camel(e) : "automatic"})';
            case "navigationDestination":
                var pad2 = ind(indent + 1);
                var contentSwift = if (args.length > 0) viewToSwift(args[0], indent + 2) else '${pad2}    Text("Destination")\n';
                'navigationDestination(for: String.self) { value in\n${contentSwift}${pad2}}';

            // --- Lifecycle modifiers (closures → bridge actions) ---
            // Use __LIFECYCLE_ACTION__ placeholder, replaced after children are processed
            case "onAppear":
                needsRuntimeBridge = true;
                'onAppear { Task.detached { HaxeBridgeC.invokeAction(__LIFECYCLE_ACTION__) } }';
            case "onDisappear":
                needsRuntimeBridge = true;
                'onDisappear { Task.detached { HaxeBridgeC.invokeAction(__LIFECYCLE_ACTION__) } }';
            case "task":
                needsRuntimeBridge = true;
                'task { HaxeBridgeC.invokeAction(__LIFECYCLE_ACTION__) }';

            case "onTapGesture":
                var actionCode = if (args.length > 0) stateActionToSwift(args[0]) else null;
                if (actionCode != null)
                    'onTapGesture { ${actionCode} }';
                else
                    'onTapGesture { }';
            case "onChange":
                // args[0] = state name (String literal), args[1] = StateAction.
                // Emits `.onChange(of: appState.<name>) { _, _ in <action> }`
                // — the body-wide appState-prefix pass doesn't reach
                // through `of:`, so we insert the prefix here.
                var stateName = if (args.length > 0) extractString(args[0]) else null;
                if (stateName == null) stateName = "";
                var actionCode = if (args.length > 1) stateActionToSwift(args[1]) else null;
                'onChange(of: appState.${stateName}) { _, _ in ${actionCode != null ? actionCode : ""} }';
            case "onAppearAction":
                var actionCode = if (args.length > 0) stateActionToSwift(args[0]) else null;
                if (actionCode != null)
                    'onAppear { ${actionCode} }';
                else
                    'onAppear { }';
            case "taskAction":
                var actionCode = if (args.length > 0) stateActionToSwift(args[0]) else null;
                if (actionCode != null)
                    'task { ${actionCode} }';
                else
                    'task { }';

            // --- Content-bearing modifiers ---
            case "sheet":
                var binding = if (args.length > 0) resolveStateName(args[0]) else "isPresented";
                var pad = ind(indent + 1);
                var contentSwift = if (args.length > 1) viewToSwift(args[1], indent + 2) else '${pad}    Text("Sheet")\n';
                'sheet(isPresented: $$${binding}) {\n${contentSwift}${pad}}';
            case "inspector":
                var binding = if (args.length > 0) resolveStateName(args[0]) else "isPresented";
                var pad = ind(indent + 1);
                var contentSwift = if (args.length > 1) viewToSwift(args[1], indent + 2) else '${pad}    Text("Inspector")\n';
                'inspector(isPresented: $$${binding}) {\n${contentSwift}${pad}}';
            case "inspectorColumnWidth":
                var mn = if (args.length > 0) extractConstant(args[0]) else null;
                var id = if (args.length > 1) extractConstant(args[1]) else null;
                var mx = if (args.length > 2) extractConstant(args[2]) else null;
                if (mn == null) mn = "200";
                if (id == null) id = "300";
                if (mx == null) mx = "600";
                'inspectorColumnWidth(min: ${mn}, ideal: ${id}, max: ${mx})';
            case "alert":
                var title = if (args.length > 0) extractString(args[0]) else "Alert";
                var binding = if (args.length > 1) resolveStateName(args[1]) else "showAlert";
                var message = if (args.length > 2) extractString(args[2]) else null;
                if (message != null)
                    'alert("${esc(title != null ? title : "")}", isPresented: $$${binding}) {} message: { Text("${esc(message)}") }';
                else
                    'alert("${esc(title != null ? title : "")}", isPresented: $$${binding}) { Button("OK") {} }';
            case "confirmationDialog":
                var title = if (args.length > 0) extractString(args[0]) else "Confirm";
                var binding = if (args.length > 1) resolveStateName(args[1]) else "showConfirm";
                var pad = ind(indent + 1);
                var contentSwift = if (args.length > 2) viewToSwift(args[2], indent + 2) else '${pad}    Button("OK") {}\n';
                'confirmationDialog("${esc(title != null ? title : "")}", isPresented: $$${binding}) {\n${contentSwift}${pad}}';
            case "searchable":
                var binding = if (args.length > 0) extractString(args[0]) else "searchText";
                var prompt = if (args.length > 1) extractString(args[1]) else null;
                if (prompt != null)
                    'searchable(text: $$${binding}, prompt: "${esc(prompt)}")';
                else
                    'searchable(text: $$${binding})';
            case "toolbar":
                var pad = ind(indent + 1);
                var contentSwift = if (args.length > 0) viewToSwift(args[0], indent + 2) else "";
                'toolbar {\n${contentSwift}${pad}}';
            case "toolbarItem":
                var placement = if (args.length > 0) extractString(args[0]) else "automatic";
                var pad = ind(indent + 1);
                var contentSwift = if (args.length > 1) viewToSwift(args[1], indent + 3) else "";
                var pad2 = ind(indent + 2);
                'toolbar {\n${pad}    ToolbarItem(placement: .${placement}) {\n${contentSwift}${pad2}}\n${pad}}';
            case "animation":
                var curve = if (args.length > 0) extractString(args[0]) else "default";
                var value = if (args.length > 1) resolveModifierValue(args, 1, null) else null;
                if (value != null)
                    'animation(.${curve != null ? curve : "default"}, value: ${value})';
                else
                    'animation(.${curve != null ? curve : "default"})';
            case "transition":
                var style = if (args.length > 0) extractString(args[0]) else "opacity";
                'transition(.${style != null ? style : "opacity"})';
            case "overlay":
                var pad = ind(indent + 1);
                var contentSwift = if (args.length > 0) viewToSwift(args[0], indent + 2) else "";
                'overlay {\n${contentSwift}${pad}}';
            case "tint":
                var e = if (args.length > 0) extractEnumName(args[0]) else null;
                'tint(${colorEnumToSwift(e, "accentColor")})';
            case "badge":
                var v = if (args.length > 0) extractConstant(args[0]) else null;
                if (v != null)
                    'badge($v)';
                else {
                    var s = if (args.length > 0) extractString(args[0]) else null;
                    s != null ? 'badge(${s})' : "badge(0)";
                }
            case "tag":
                // A typed lambda item ref inside a closure-form ForEach
                // is emitted as a raw Swift expression (no quotes) so
                // `.tag(item)` binds to the iterated value. Constant
                // string args remain literal-quoted as before.
                var rawExpr = if (args.length > 0) extractItemExpr(args[0]) else null;
                if (rawExpr != null) 'tag(${rawExpr})';
                else {
                    var s = if (args.length > 0) extractString(args[0]) else null;
                    s != null ? 'tag("${esc(s)}")' : 'tag("")';
                }

            // --- Visual effects (accept constants or state variable names) ---
            case "blur":
                var v = resolveModifierValue(args, 0, "3");
                'blur(radius: $v)';
            case "scaleEffect":
                var v = resolveModifierValue(args, 0, "1.0");
                'scaleEffect($v)';
            case "rotationEffect":
                var v = resolveModifierValue(args, 0, "0");
                'rotationEffect(.degrees($v))';
            case "offset":
                var x = resolveModifierValue(args, 0, "0");
                var y = resolveModifierValue(args, 1, "0");
                'offset(x: $x, y: $y)';

            // --- Image effects ---
            case "brightness":
                var v = resolveModifierValue(args, 0, "0");
                'brightness($v)';
            case "contrast":
                var v = resolveModifierValue(args, 0, "1");
                'contrast($v)';
            case "saturation":
                var v = resolveModifierValue(args, 0, "1");
                'saturation($v)';
            case "grayscale":
                var v = resolveModifierValue(args, 0, "0");
                'grayscale($v)';

            // --- Presentation ---
            case "popover":
                var binding = if (args.length > 0) resolveStateName(args[0]) else "isPresented";
                var pad2 = ind(indent + 1);
                var contentSwift = if (args.length > 1) viewToSwift(args[1], indent + 2) else '${pad2}    Text("Popover")\n';
                'popover(isPresented: $$${binding}) {\n${contentSwift}${pad2}}';
            case "fullScreenCover":
                var binding = if (args.length > 0) resolveStateName(args[0]) else "isPresented";
                var pad2 = ind(indent + 1);
                var contentSwift = if (args.length > 1) viewToSwift(args[1], indent + 2) else '${pad2}    Text("Content")\n';
                'fullScreenCover(isPresented: $$${binding}) {\n${contentSwift}${pad2}}';
            case "contextMenu":
                var pad2 = ind(indent + 1);
                var contentSwift = if (args.length > 0) viewToSwift(args[0], indent + 2) else "";
                'contextMenu {\n${contentSwift}${pad2}}';

            // --- List ---
            case "swipeActions":
                var pad2 = ind(indent + 1);
                var contentSwift = if (args.length > 0) viewToSwift(args[0], indent + 2) else "";
                'swipeActions {\n${contentSwift}${pad2}}';
            case "refreshable":
                needsRuntimeBridge = true;
                'refreshable { Task.detached { HaxeBridgeC.invokeAction(__LIFECYCLE_ACTION__) } }';
            case "listStyle":
                var s = if (args.length > 0) extractString(args[0]) else "automatic";
                'listStyle(.${s != null ? s : "automatic"})';

            // --- Layout ---
            case "aspectRatio":
                var r = if (args.length > 0) extractConstant(args[0]) else null;
                var mode = if (args.length > 1) extractString(args[1]) else "fit";
                if (r != null)
                    'aspectRatio($r, contentMode: .${mode != null ? mode : "fit"})';
                else
                    'aspectRatio(contentMode: .${mode != null ? mode : "fit"})';

            // --- Accessibility ---
            case "accessibilityLabel":
                var s = if (args.length > 0) extractString(args[0]) else "";
                'accessibilityLabel("${esc(s != null ? s : "")}")';
            case "help":
                var s = if (args.length > 0) extractString(args[0]) else "";
                'help("${esc(s != null ? s : "")}")';

            // --- Interaction ---
            case "onSubmit":
                needsRuntimeBridge = true;
                'onSubmit { Task.detached { HaxeBridgeC.invokeAction(__LIFECYCLE_ACTION__) } }';
            case "onLongPressGesture":
                var actionCode = if (args.length > 0) stateActionToSwift(args[0]) else null;
                if (actionCode != null)
                    'onLongPressGesture { ${actionCode} }';
                else
                    'onLongPressGesture { }';
            case "keyboardShortcut":
                // args[0]: key string. args[1]: modifiers Array<String>.
                // Emits `.keyboardShortcut(KeyEquivalent("k"), modifiers: [.command, ...])`
                // — the named-key sentinels resolve to `.return`, `.escape`,
                // `.delete`, `.tab`, `.space`, `.leftArrow`, `.rightArrow`,
                // `.upArrow`, `.downArrow`; everything else maps directly to
                // `KeyEquivalent("<char>")`.
                var key = if (args.length > 0) extractString(args[0]) else null;
                if (key == null) key = "";
                var keyExpr = keyEquivalentToSwift(key);
                var mods:Array<String> = [];
                if (args.length > 1) {
                    var arrE = unwrap(args[1]);
                    switch (arrE.expr) {
                        case TArrayDecl(elems):
                            for (el in elems) {
                                var s = extractString(el);
                                if (s != null) {
                                    var swift = modifierKeyToSwift(s);
                                    if (swift != null) mods.push(swift);
                                }
                            }
                        default:
                    }
                }
                if (mods.length > 0)
                    'keyboardShortcut(${keyExpr}, modifiers: [${mods.join(", ")}])';
                else
                    'keyboardShortcut(${keyExpr})';
            case "onKeyPress":
                // args[0]: key name (String). args[1]: StateAction.
                // Emits `.onKeyPress(<keyEquivalent>) { <action>; return .handled }`
                // — `.handled` stops SwiftUI bubbling the event up the
                // focus chain, the right default for an explicit handler.
                var key = if (args.length > 0) extractString(args[0]) else "";
                if (key == null) key = "";
                var keyExpr = keyEquivalentToSwift(key);
                var actionCode = if (args.length > 1) stateActionToSwift(args[1]) else "";
                'onKeyPress(${keyExpr}) { ${actionCode}; return .handled }';

            default:
                // Generic: try to pass through args
                if (args.length == 0) '${name}()';
                else {
                    var vals = [for (a in args) { var c = extractConstant(a); c != null ? c : { var e = extractEnumName(a); e != null ? '.${camel(e)}' : "/* expr */"; }; }];
                    '${name}(${vals.join(", ")})';
                }
        }
    }

    // ── Extraction helpers ──────────────────────────────────────────

    static function faName(fa:haxe.macro.Type.FieldAccess):String {
        return switch (fa) {
            case FInstance(_, _, cf) | FStatic(_, cf) | FClosure(_, cf) | FAnon(cf): cf.get().name;
            case FDynamic(s): s;
            case FEnum(_, ef): ef.name;
        }
    }

    static function extractFieldName(expr:haxe.macro.Type.TypedExpr):String {
        return switch (expr.expr) {
            case TField(_, fa): faName(fa);
            default: null;
        }
    }

    static function extractString(expr:haxe.macro.Type.TypedExpr):String {
        if (expr == null) return null;
        return switch (expr.expr) {
            case TConst(TString(s)): s;
            case TCast(e, _): extractString(e);
            case TParenthesis(e): extractString(e);
            case TLocal(v):
                if (localBindings.exists(v.id))
                    extractString(localBindings.get(v.id));
                else
                    null;
            default: null;
        }
    }

    static function extractConstant(expr:haxe.macro.Type.TypedExpr):String {
        if (expr == null) return null;
        return switch (expr.expr) {
            case TConst(c): switch (c) {
                case TString(s): '"${esc(s)}"';
                case TInt(v): Std.string(v);
                case TFloat(v): v;
                case TBool(b): b ? "true" : "false";
                default: null;
            }
            case TCast(e, _): extractConstant(e);
            case TParenthesis(e): extractConstant(e);
            case TLocal(v):
                if (localBindings.exists(v.id))
                    extractConstant(localBindings.get(v.id));
                else
                    null;
            default: null;
        }
    }

    /** Extract bridge call arguments: supports a single string or an array of constants. **/
    /** Resolve a modifier argument: number (literal) or string (state variable name, emitted bare). **/
    static function resolveModifierValue(args:Array<haxe.macro.Type.TypedExpr>, index:Int, defaultVal:String):String {
        if (index >= args.length) return defaultVal;
        // Closure-form ForEach item refs (`item`, `other.value[i]`)
        // take priority over the legacy string/field paths.
        var itemExpr = extractItemExpr(args[index]);
        if (itemExpr != null) return itemExpr;
        var e = unwrap(args[index]);
        switch (e.expr) {
            case TConst(c):
                switch (c) {
                    case TInt(v): return Std.string(v);
                    case TFloat(v): return v;
                    case TBool(b): return b ? "true" : "false";
                    case TString(s): return s; // backward compat: string as state name
                    default:
                }
            case TField(_, fa):
                // State<T> field reference — extract field name
                switch (fa) {
                    case FInstance(_, _, fieldRef): return fieldRef.get().name;
                    case FStatic(_, fieldRef): return fieldRef.get().name;
                    default:
                }
            default:
                // Check for TLocal referencing a field (common with @:state)
                var fieldName = extractThisField(e);
                if (fieldName != null) return fieldName;
        }
        return defaultVal;
    }

    /** Resolve the hex/colour expression for `foregroundHex` /
        `backgroundHex`. Tries the typed closure-form item ref first
        (so the body can pass a lambda param or `other.value[i]`),
        then falls back to the legacy string literal which the
        appState-prefix pass rewrites bare names in. **/
    static function resolveHexExpr(args:Array<haxe.macro.Type.TypedExpr>):String {
        if (args.length == 0) return "\"\"";
        // 1. Closure-form lambda item ref ("item", "other.value[i]")
        var itemExpr = extractItemExpr(args[0]);
        if (itemExpr != null) return itemExpr;
        // 2. Direct State<String> field reference (`.foregroundHex(myColorState)`).
        //    Emit `appState.<name>` straight away — the
        //    body-wide appState-prefix pass keys on bracket /
        //    interpolation / assignment patterns and doesn't match
        //    bare names inside `Color(suiHex: …)`, so we have to
        //    insert the prefix here ourselves.
        var e = unwrap(args[0]);
        switch (e.expr) {
            case TField(_, fa):
                switch (fa) {
                    case FInstance(_, _, fieldRef): return 'appState.${fieldRef.get().name}';
                    case FStatic(_, fieldRef): return 'appState.${fieldRef.get().name}';
                    default:
                }
            default:
                var fieldName = extractThisField(e);
                if (fieldName != null) return 'appState.${fieldName}';
        }
        // 3. Legacy: string literal embedded verbatim.
        var s = extractString(args[0]);
        return s != null ? s : "\"\"";
    }

    static function extractBridgeArgs(expr:haxe.macro.Type.TypedExpr):String {
        if (expr == null) return "";
        var e = unwrap(expr);
        switch (e.expr) {
            case TArrayDecl(elements):
                var parts:Array<String> = [];
                for (el in elements) {
                    var c = extractConstant(el);
                    if (c != null) parts.push(c);
                }
                return parts.join(", ");
            default:
                var s = extractString(expr);
                if (s != null) return '"${esc(s)}"';
                var c = extractConstant(expr);
                if (c != null) return c;
                return "";
        }
    }

    /** Extract a `this.fieldName` reference → returns the field name. **/
    static function extractThisField(expr:haxe.macro.Type.TypedExpr):String {
        var e = unwrap(expr);
        return switch (e.expr) {
            case TField(inner, fa):
                var innerU = unwrap(inner);
                switch (innerU.expr) {
                    case TConst(TThis): faName(fa);
                    default: null;
                }
            default: null;
        }
    }

    static function extractEnumName(expr:haxe.macro.Type.TypedExpr):String {
        return switch (expr.expr) {
            case TField(_, fa): switch (fa) {
                case FEnum(_, ef): ef.name;
                default: null;
            }
            default: null;
        }
    }

    // ── Type helpers ────────────────────────────────────────────────

    static function haxeTypeToSwift(type:haxe.macro.Type):String {
        return switch (type) {
            case TInst(ref, params):
                var name = ref.get().name;
                switch (name) {
                    case "String": "String";
                    case "Array":
                        if (params.length > 0)
                            '[${haxeTypeToSwift(params[0])}]';
                        else
                            "[Any]";
                    default: name;
                }
            case TAbstract(ref, _): switch (ref.get().name) {
                case "Int": "Int";
                case "Float": "Double";
                case "Bool": "Bool";
                case "Null":
                    // Null<T> → T? but for State we just use T
                    "Any";
                default: ref.get().name;
            }
            default: "Any";
        }
    }

    static function swiftDefault(swiftType:String):String {
        if (swiftType.charAt(0) == "[") return "[]"; // array types
        return switch (swiftType) {
            case "Int": "0";
            case "Double" | "Float": "0.0";
            case "Bool": "false";
            case "String": '""';
            default: swiftType + "()";
        }
    }

    // ── String helpers ──────────────────────────────────────────────

    static function esc(s:String):String {
        if (s == null) return "";
        return s.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n");
    }

    static function camel(s:String):String {
        if (s == null || s.length == 0) return s;
        return s.charAt(0).toLowerCase() + s.substr(1);
    }

    /** Translate a `ColorValue` enum-name into the Swift expression to
        pass to a colour-consuming modifier (`foregroundStyle`,
        `background`, `shadow`, `tint`, etc.). Most values map to the
        dotted shorthand (`.red`, `.blue`, `.primary`, …) because
        SwiftUI exposes them on every relevant `ShapeStyle`/`Color`
        type. `Accent` is the exception: there is no `.accent`
        `ShapeStyle` member, so we emit the explicit static
        `Color.accentColor` instead, which is universally available
        and works as both a `Color` and a `ShapeStyle`. **/
    static function colorEnumToSwift(name:Null<String>, fallback:String):String {
        if (name == null) return '.${fallback}';
        return switch (name) {
            case "Accent": "Color.accentColor";
            default: '.${camel(name)}';
        };
    }

    /** Map a sui key-name string to the matching SwiftUI
        `KeyEquivalent`. Used by both `.keyboardShortcut` and
        `.onKeyPress`. Named keys (return, escape, …) resolve to
        their static properties; anything else is wrapped in
        `KeyEquivalent("<char>")`. **/
    static function keyEquivalentToSwift(key:String):String {
        return switch (key.toLowerCase()) {
            case "return": ".return";
            case "escape": ".escape";
            case "delete" | "backspace": ".delete";
            case "tab": ".tab";
            case "space": ".space";
            case "left": ".leftArrow";
            case "right": ".rightArrow";
            case "up": ".upArrow";
            case "down": ".downArrow";
            case "home": ".home";
            case "end": ".end";
            case "pageup": ".pageUp";
            case "pagedown": ".pageDown";
            default: 'KeyEquivalent("${esc(key)}")';
        };
    }

    /** Map a sui modifier-key name to its `EventModifiers` member. **/
    static function modifierKeyToSwift(name:String):Null<String> {
        return switch (name.toLowerCase()) {
            case "command" | "cmd": ".command";
            case "option" | "alt": ".option";
            case "control" | "ctrl": ".control";
            case "shift": ".shift";
            case "capslock": ".capsLock";
            default: null;
        };
    }

    /** Translate a TArrayDecl of `ColorValue` enum constants into a
        Swift literal `[.red, .blue, …]`. Used by the gradient
        views. Unknown / non-enum entries fall through to
        `.primary` to keep the array length matched. **/
    static function extractColorArrayToSwift(expr:haxe.macro.Type.TypedExpr):String {
        if (expr == null) return "[]";
        var e = unwrap(expr);
        switch (e.expr) {
            case TArrayDecl(elems):
                var parts:Array<String> = [];
                for (el in elems) {
                    var name = extractEnumName(el);
                    parts.push(name != null ? '.${camel(name)}' : ".primary");
                }
                return '[${parts.join(", ")}]';
            default:
        }
        return "[]";
    }

    static function templateToSwift(template:String):String {
        var buf = new StringBuf();
        buf.add('"');
        var i = 0;
        while (i < template.length) {
            var ch = template.charAt(i);
            if (ch == "{") {
                var end = template.indexOf("}", i);
                if (end != -1) {
                    buf.add("\\(");
                    buf.add(template.substr(i + 1, end - i - 1));
                    buf.add(")");
                    i = end + 1;
                    continue;
                }
            }
            if (ch == '"') buf.add("\\");
            if (ch == "\\") buf.add("\\");
            buf.add(ch);
            i++;
        }
        buf.add('"');
        return buf.toString();
    }

    static function ind(level:Int):String {
        var s = "";
        for (_ in 0...level) s += "    ";
        return s;
    }

    static function ensureDir(path:String):Void {
        var parts = path.split("/");
        var current = "";
        for (part in parts) {
            if (part == "") continue;
            current = current == "" ? part : '$current/$part';
            if (!sys.FileSystem.exists(current))
                sys.FileSystem.createDirectory(current);
        }
    }

    #end // #if macro
}
