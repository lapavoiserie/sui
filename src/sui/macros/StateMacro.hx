package sui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;

/**
    Build macro for App / ViewComponent subclasses that:
    1. Transforms `@:state` fields into `State<T>` fields with
       constructor initialisation.
    2. Walks every method body to find calls to *bridged modifiers*
       (`foregroundHex`, `backgroundHex`, …). If a call's argument
       is "complex" (anything beyond a literal string or a typed
       state reference), the argument expression is captured,
       state references inside it are qualified against the App
       instance, lambda parameters from enclosing `ForEach` scopes
       become function parameters, and a `@:expose static`
       wrapper is synthesised on this class. The call site is
       replaced with a sentinel-encoded string that the Swift
       generator dispatches into a `HaxeBridgeC.<funcName>(args)`
       call.
    3. Wires every *action closure* (Button actions, `.onTapGesture`,
       `.onChange`, lifecycle closures, …) to the runtime dispatch
       store with a stable compile-time id:
       - outside `ForEach` row templates the call site becomes
         `Callbacks.reg(<id>, <closure>)` — registration happens when
         the view tree is built and Swift dispatches
         `HaxeBridgeC.invokeAction(<id>)`;
       - inside a `ForEach` row template (which never executes at
         runtime — SwiftUI iterates on its side) the closure is
         lifted into a static *builder* `(__i0, __i1) -> (() -> Void)`
         that re-materialises the iteration values from the row
         indices. The call site becomes the inert marker
         `Callbacks.indexed(<id>, <frames>)` and Swift dispatches
         `HaxeBridgeC.invokeIndexedAction(<id>, i0, i1)` with the
         live loop indices.

    The user writes plain Haxe; the macro takes care of everything.
**/
class StateMacro {
    /** Modifiers whose argument(s) are bridged when complex,
        mapped to the synthesised wrapper's return type. String
        for hex-coloured modifiers, Float for numeric ones (offsets,
        opacity, scale, …). Mirror keys in
        `SwiftGenerator.SUI_BRIDGE_PREFIX` dispatcher. **/
    static final BRIDGED_MODIFIERS = [
        "foregroundHex" => "String",
        "backgroundHex" => "String",
        "opacity" => "Float",
        "scaleEffect" => "Float",
        "rotationEffect" => "Float",
        "blur" => "Float",
        "brightness" => "Float",
        "contrast" => "Float",
        "saturation" => "Float",
        "grayscale" => "Float",
    ];

    /** Multi-arg modifiers — every argument is independently bridged
        when complex. Values map to return type per axis. **/
    static final BRIDGED_MODIFIERS_MULTI = [
        "offset" => "Float",
        "proportionalOffset" => "Float",
        "proportionalFrame" => "Float",
    ];

    /** View methods whose argument at the given index is an action
        closure (`() -> Void`) that must be wired to the runtime
        dispatch store. Mirrors the emission sites in
        `SwiftGenerator.modToSwift`. **/
    static final ACTION_MODIFIERS = [
        "onTapGesture" => 0,
        "onLongPressGesture" => 0,
        "onChange" => 1,
        "onKeyPress" => 1,
        "onAppearAction" => 0,
        "taskAction" => 0,
        "every" => 1,
        "onAppear" => 0,
        "onDisappear" => 0,
        "task" => 0,
        "onSubmit" => 0,
        "refreshable" => 0,
    ];

    static var synthesisedExprs:Map<String, SynthesisedExpr>;
    /** Builders lifted from action closures inside ForEach row
        templates, in walk order. Each entry carries the static
        function field to append plus its registration id. **/
    static var synthesisedBuilders:Array<{id:Int, fnName:String, field:Field}>;
    /** Occurrence counter per closure source text, used to salt the
        stable action id so two identical closures at different call
        sites get distinct ids. **/
    static var actionIdOccurrences:Map<String, Int>;
    /** Map state field name → inner type T of `State<T>`. The
        Swift binding lives on `appState.<name>`; for value-typed
        bindings (String / Int / Float / Bool) the walker passes
        the Swift value into the synthesised wrapper as a parameter
        so reads see the current SwiftUI binding rather than the
        possibly-stale Haxe mirror. Array / object state stays on
        the Haxe side (`App.instance.<name>.value`). **/
    static var stateFieldTypes:Map<String, ComplexType>;
    static var stateFieldNames:Map<String, Bool>;
    /** Non-static members of the class being built (methods and
        plain fields). Builders lifted from ForEach action closures
        are static, so references to these are qualified through
        `<ClassName>.instance` just like state fields. **/
    static var instanceMemberNames:Map<String, Bool>;
    static var className:String;
    /** Set whenever a synthesised wrapper or builder qualifies a
        state reference to `<ClassName>.instance.<field>` — triggers
        synthesis of the `instance` static if the user didn't
        declare one. **/
    static var needsInstance:Bool = false;

    public static function build():Array<Field> {
        synthesisedExprs = new Map();
        synthesisedBuilders = [];
        actionIdOccurrences = new Map();
        needsInstance = false;
        stateFieldNames = new Map();
        stateFieldTypes = new Map();
        className = {
            var cls = Context.getLocalClass();
            cls != null ? cls.get().name : "";
        };

        var fields = Context.getBuildFields();
        var stateInits:Array<Expr> = [];
        var newFields:Array<Field> = [];

        // Collect non-static member names for builder qualification.
        instanceMemberNames = new Map();
        for (field in fields) {
            if (field.name == "new") continue;
            var isStatic = field.access != null && field.access.indexOf(AStatic) != -1;
            if (!isStatic) instanceMemberNames.set(field.name, true);
        }

        // First pass: collect every state-typed field name and its
        // inner type T (both `@:state var x:T` and manual `var
        // x:State<T>`).
        for (field in fields) {
            switch (field.kind) {
                case FVar(t, _):
                    var inner = stateInnerType(t);
                    if (inner != null) {
                        stateFieldNames.set(field.name, true);
                        stateFieldTypes.set(field.name, inner);
                    }
                case FProp(_, _, t, _):
                    var inner = stateInnerType(t);
                    if (inner != null) {
                        stateFieldNames.set(field.name, true);
                        stateFieldTypes.set(field.name, inner);
                    }
                default:
            }
        }
        // Also `@:state` fields use their raw T — collect later as
        // we process them (loop below).

        for (field in fields) {
            var isState = false;
            if (field.meta != null) {
                for (m in field.meta) {
                    if (m.name == ":state") {
                        isState = true;
                        break;
                    }
                }
            }

            if (!isState) {
                newFields.push(field);
                continue;
            }

            var origType:Null<ComplexType> = null;
            var defaultExpr:Null<Expr> = null;
            switch (field.kind) {
                case FVar(t, e):
                    origType = t;
                    defaultExpr = e;
                default:
            }

            if (origType == null) {
                Context.error("@:state fields must have an explicit type", field.pos);
                continue;
            }

            if (defaultExpr == null) {
                defaultExpr = macro null;
            }

            var fieldName = field.name;
            stateFieldNames.set(fieldName, true);

            var stateType:ComplexType = TPath({
                pack: ["sui", "state"],
                name: "State",
                params: [TPType(origType)]
            });

            newFields.push({
                name: field.name,
                access: field.access,
                kind: FVar(stateType, null),
                pos: field.pos,
                meta: field.meta,
                doc: field.doc,
            });

            var nameExpr = macro $v{fieldName};
            stateInits.push(macro $i{fieldName} = new sui.state.State($defaultExpr, $nameExpr));
        }

        // Walk every method body, replacing bridged-modifier calls
        // with sentinel strings, wiring action closures to the
        // runtime dispatch store and synthesising wrappers/builders.
        // Runs BEFORE constructor injection so the walk results
        // (builder registrations, `instance` synthesis) can be
        // injected alongside the state inits.
        for (f in newFields) {
            switch (f.kind) {
                case FFun(func) if (func.expr != null):
                    func.expr = walk(func.expr, new Map(), []);
                default:
            }
        }

        var ctorInjects:Array<Expr> = [];

        // Synthesise a static `instance` when generated code
        // references `<ClassName>.instance` (state refs qualified
        // inside synthesised wrappers and ForEach action builders)
        // and the user didn't declare one themselves.
        if (needsInstance) {
            var hasInstance = false;
            for (f in fields) if (f.name == "instance") { hasInstance = true; break; }
            if (!hasInstance) {
                newFields.push({
                    name: "instance",
                    access: [APublic, AStatic],
                    kind: FVar(TPath({pack: [], name: className}), null),
                    pos: Context.currentPos(),
                    doc: "Synthesised by StateMacro — the app/component singleton that qualified state references resolve through.",
                });
                ctorInjects.push(macro instance = this);
            }
        }

        for (e in stateInits) ctorInjects.push(e);

        // Builder registrations run from the constructor — the view
        // tree is built once at boot, so the ctor always runs before
        // any dispatch can arrive from Swift.
        for (b in synthesisedBuilders)
            ctorInjects.push(macro sui.state.Callbacks.registerIndexed($v{b.id}, $i{b.fnName}));

        if (ctorInjects.length > 0) {
            var ctorFound = false;
            for (f in newFields) {
                if (f.name == "new") {
                    ctorFound = true;
                    switch (f.kind) {
                        case FFun(func):
                            var existingBody = func.expr;
                            var allExprs:Array<Expr> = ctorInjects.copy();
                            if (existingBody != null) allExprs.push(existingBody);
                            func.expr = macro $b{allExprs};
                        default:
                    }
                    break;
                }
            }

            if (!ctorFound) {
                var allExprs:Array<Expr> = [macro super()];
                for (e in ctorInjects) allExprs.push(e);
                newFields.push({
                    name: "new",
                    access: [APublic],
                    kind: FFun({
                        args: [],
                        ret: null,
                        expr: macro $b{allExprs},
                    }),
                    pos: Context.currentPos(),
                });
            }
        }

        // Append the lifted ForEach action builders.
        for (b in synthesisedBuilders) newFields.push(b.field);

        // Append the synthesised wrapper functions. Parameter
        // order: lambda params (Int) first, then primitive state
        // reads. If neither is present, fall back to the legacy
        // single-String "_unused" slot so the bridge generator
        // emits a stable signature.
        for (entry in synthesisedExprs.keyValueIterator()) {
            var funcName = entry.key;
            var s = entry.value;
            var args:Array<FunctionArg> = [for (p in s.params) {name: p, type: macro :Int}];
            if (s.primReads != null) {
                for (p in s.primReads) args.push({name: p.name, type: p.type});
            }
            if (args.length == 0) {
                args.push({name: "_unused", type: macro :String});
            }
            var ret:ComplexType = s.returnType != null ? s.returnType : macro :String;
            newFields.push({
                name: funcName,
                access: [APublic, AStatic],
                meta: [{name: ":expose", pos: s.pos}],
                kind: FFun({
                    args: args,
                    ret: ret,
                    expr: macro return $e{s.expr},
                }),
                pos: s.pos,
            });
        }

        return newFields;
    }

    /** Walk an Expr tree, tracking lambda-param scope (from
        ForEach legacy `"i"` form, closure form and `byIndex`) plus
        the stack of enclosing ForEach frames, and rewrite:
        - bridged-modifier calls with a complex argument
        - action-closure call sites (Button / action modifiers)
        Bridged modifiers synthesise an `@:expose static` wrapper on
        the App class and replace the call site with a sentinel
        string; action closures are wired through
        `sui.state.Callbacks` (see class doc). **/
    static function walk(e:Expr, scope:Map<String, Bool>, frames:Array<ForEachFrame>):Expr {
        return switch (e.expr) {
            // ForEach legacy form: ENew("ForEach", [arr, "i", body])
            case ENew(t, args) if (t.name == "ForEach" && args.length == 3):
                switch (args[1].expr) {
                    case EConst(CString(idx)):
                        var newScope = copyScope(scope);
                        newScope.set(idx, true);
                        var newFrames = frames.concat([{param: idx, isIndex: true, arr: args[0], pos: e.pos}]);
                        var newArr = walk(args[0], scope, frames);
                        var newBody = walk(args[2], newScope, newFrames);
                        {expr: ENew(t, [newArr, args[1], newBody]), pos: e.pos};
                    default:
                        defaultRecurse(e, scope, frames);
                }
            // ForEach closure form: ENew("ForEach", [arr, item -> body])
            case ENew(t, args) if (t.name == "ForEach" && args.length == 2):
                switch (args[1].expr) {
                    case EFunction(kind, fn):
                        var newScope = copyScope(scope);
                        for (a in fn.args) newScope.set(a.name, true);
                        var newFrames = frames;
                        if (fn.args.length == 1)
                            newFrames = frames.concat([{param: fn.args[0].name, isIndex: false, arr: args[0], pos: e.pos}]);
                        var newArr = walk(args[0], scope, frames);
                        var newFn:Function = {args: fn.args, ret: fn.ret, expr: walk(fn.expr, newScope, newFrames)};
                        var newLambda:Expr = {expr: EFunction(kind, newFn), pos: args[1].pos};
                        {expr: ENew(t, [newArr, newLambda]), pos: e.pos};
                    default:
                        defaultRecurse(e, scope, frames);
                }
            // ForEach.byIndex(arr, i -> body) — the lambda param IS the index.
            case ECall(callee = {expr: EField(_, "byIndex")}, args)
                if (args.length == 2 && isForEachReceiver(callee)):
                switch (args[1].expr) {
                    case EFunction(kind, fn) if (fn.args.length == 1):
                        var newScope = copyScope(scope);
                        newScope.set(fn.args[0].name, true);
                        var newFrames = frames.concat([{param: fn.args[0].name, isIndex: true, arr: args[0], pos: e.pos}]);
                        var newArr = walk(args[0], scope, frames);
                        var newFn:Function = {args: fn.args, ret: fn.ret, expr: walk(fn.expr, newScope, newFrames)};
                        var newLambda:Expr = {expr: EFunction(kind, newFn), pos: args[1].pos};
                        {expr: ECall(callee, [newArr, newLambda]), pos: e.pos};
                    default:
                        defaultRecurse(e, scope, frames);
                }
            // Button construction: new Button(label, action)
            case ENew(t, args) if (t.name == "Button" && args.length >= 2):
                var newArgs = [walk(args[0], scope, frames), wrapAction(args[1], scope, frames)];
                for (i in 2...args.length) newArgs.push(walk(args[i], scope, frames));
                {expr: ENew(t, newArgs), pos: e.pos};
            // Button.withView(labelView, action)
            case ECall(callee = {expr: EField({expr: EConst(CIdent("Button"))}, "withView")}, args) if (args.length >= 2):
                var newArgs = [walk(args[0], scope, frames), wrapAction(args[1], scope, frames)];
                for (i in 2...args.length) newArgs.push(walk(args[i], scope, frames));
                {expr: ECall(callee, newArgs), pos: e.pos};
            // Action-taking view modifiers: .onTapGesture(cb), .onChange(name, cb), …
            case ECall(callee = {expr: EField(_, modName)}, args)
                if (ACTION_MODIFIERS.exists(modName) && args.length > ACTION_MODIFIERS.get(modName)):
                var actionIdx = ACTION_MODIFIERS.get(modName);
                var newReceiver = walkCallee(callee, scope, frames);
                var newArgs = [for (i in 0...args.length)
                    i == actionIdx ? wrapAction(args[i], scope, frames) : walk(args[i], scope, frames)];
                {expr: ECall(newReceiver, newArgs), pos: e.pos};
            // Bridged single-arg modifier: <view>.foregroundHex(<arg>)
            case ECall(callee, args) if (args.length == 1 && isBridgedModifierCallee(callee, BRIDGED_MODIFIERS)):
                var arg = args[0];
                var newReceiver = walkCallee(callee, scope, frames);
                var retType = lookupReturnType(callee, BRIDGED_MODIFIERS);
                var newArg = maybeBridge(arg, scope, frames, retType);
                {expr: ECall(newReceiver, [newArg]), pos: e.pos};
            // Bridged multi-arg modifier: <view>.proportionalOffset(<x>, <y>)
            case ECall(callee, args) if (isBridgedModifierCallee(callee, BRIDGED_MODIFIERS_MULTI)):
                var newReceiver = walkCallee(callee, scope, frames);
                var retType = lookupReturnType(callee, BRIDGED_MODIFIERS_MULTI);
                var newArgs = [for (a in args) maybeBridge(a, scope, frames, retType)];
                {expr: ECall(newReceiver, newArgs), pos: e.pos};
            // Generic recursion with scope-aware EFunction handling.
            case EFunction(kind, fn):
                var newScope = copyScope(scope);
                for (a in fn.args) newScope.set(a.name, true);
                var newFn:Function = {args: fn.args, ret: fn.ret, expr: walk(fn.expr, newScope, frames)};
                {expr: EFunction(kind, newFn), pos: e.pos};
            default:
                defaultRecurse(e, scope, frames);
        };
    }

    /** True when `callee` is a static access on the `ForEach` class
        (`ForEach.byIndex` or `sui.ui.ForEach.byIndex`). **/
    static function isForEachReceiver(callee:Expr):Bool {
        return switch (callee.expr) {
            case EField(recv, _):
                switch (recv.expr) {
                    case EConst(CIdent("ForEach")): true;
                    case EField(_, "ForEach"): true;
                    default: false;
                }
            default: false;
        };
    }

    /** Wire an action argument to the runtime dispatch store.

        Outside a ForEach row template:
            `<closure>` → `Callbacks.reg(<id>, <closure>)`
        Registration happens when the view tree is built; the Swift
        side dispatches `invokeAction(<id>)` with the same id, read
        back from the typed AST by SwiftGenerator — no parallel
        counters.

        Inside one (or two nested) ForEach row templates the closure
        is lifted into a static builder
        `(__i0:Int, __i1:Int) -> (() -> Void)` on this class. The
        builder re-declares each frame's iteration value from the
        row indices (Haxe's own closure-capture machinery does the
        rest — multi-statement bodies, captures of states via
        `<ClassName>.instance`, partial application all work), and
        the call site becomes the inert marker
        `Callbacks.indexed(<id>, <frames>)`.

        Constraints inside row templates: the closure may reference
        the iteration params, `@:state` fields and statics — but not
        instance members or locals of the enclosing method (the
        builder is static and runs at tap time). **/
    static function wrapAction(arg:Expr, scope:Map<String, Bool>, frames:Array<ForEachFrame>):Expr {
        switch (arg.expr) {
            case EConst(CIdent("null")): return arg;
            default:
        }
        var walked = walk(arg, scope, frames);
        var id = stableActionId(arg);

        if (frames.length == 0)
            return macro @:pos(arg.pos) sui.state.Callbacks.reg($v{id}, $walked);

        if (frames.length > 2)
            Context.error("[sui] Action closures support at most two nested ForEach levels", arg.pos);

        // Re-declare each frame's iteration value from the builder's
        // index parameters, outermost first.
        var decls:Array<Expr> = [];
        for (j in 0...frames.length) {
            var f = frames[j];
            var idxIdent:Expr = {expr: EConst(CIdent('__i$j')), pos: arg.pos};
            if (f.isIndex) {
                decls.push({
                    expr: EVars([{name: f.param, type: macro :Int, expr: idxIdent}]),
                    pos: arg.pos,
                });
            } else {
                var stateName = stateNameOfExpr(f.arr);
                if (stateName == null)
                    Context.error("[sui] Action closures inside a closure-form ForEach require the iterated array to be a @:state field", arg.pos);
                needsInstance = true;
                var arrAccess = {
                    var clsExpr:Expr = {expr: EConst(CIdent(className)), pos: arg.pos};
                    var instExpr:Expr = {expr: EField(clsExpr, "instance"), pos: arg.pos};
                    var fieldExpr:Expr = {expr: EField(instExpr, stateName), pos: arg.pos};
                    var valueExpr:Expr = {expr: EField(fieldExpr, "value"), pos: arg.pos};
                    {expr: EArray(valueExpr, idxIdent), pos: arg.pos};
                };
                decls.push({
                    expr: EVars([{name: f.param, type: null, expr: arrAccess}]),
                    pos: arg.pos,
                });
            }
        }

        // Qualify bare state refs inside the closure so the static
        // builder resolves them through `<ClassName>.instance`.
        // Frame params (and any other lambda params in scope) are
        // skipped — they're builder locals now.
        var qualified = qualifyStateRefs(walked, scope);

        var fnName = '_sui_cb_${StringTools.hex(id, 8).toLowerCase()}';
        var bodyExprs:Array<Expr> = decls.copy();
        bodyExprs.push(macro @:pos(arg.pos) return $qualified);

        synthesisedBuilders.push({
            id: id,
            fnName: fnName,
            field: {
                name: fnName,
                access: [APublic, AStatic],
                kind: FFun({
                    args: [
                        {name: "__i0", type: macro :Int},
                        {name: "__i1", type: macro :Int},
                    ],
                    ret: macro :() -> Void,
                    expr: macro $b{bodyExprs},
                }),
                pos: arg.pos,
                doc: "Synthesised by StateMacro — builder for a ForEach row action closure.",
            },
        });

        return macro @:pos(arg.pos) sui.state.Callbacks.indexed($v{id}, $v{frames.length});
    }

    /** Resolve a state-field name from an expression that references
        it — bare ident (`todos`) or `this.todos`. **/
    static function stateNameOfExpr(e:Expr):Null<String> {
        if (e == null) return null;
        return switch (e.expr) {
            case EConst(CIdent(name)) if (stateFieldNames.exists(name)): name;
            case EField({expr: EConst(CIdent("this"))}, name) if (stateFieldNames.exists(name)): name;
            case EParenthesis(inner): stateNameOfExpr(inner);
            default: null;
        };
    }

    /** Stable 31-bit id for an action call site: content hash of the
        closure source, salted with the class name and an occurrence
        counter so identical closures at different call sites stay
        distinct. Content-derived (not a global counter) so partial
        rebuilds under the compilation server can't shift ids between
        cached and re-typed modules. **/
    static function stableActionId(arg:Expr):Int {
        var src = className + "::" + ExprTools.toString(arg);
        var n = actionIdOccurrences.exists(src) ? actionIdOccurrences.get(src) : 0;
        actionIdOccurrences.set(src, n + 1);
        var salted = src + "#" + n;
        var h:Int = 0x811c9dc5;
        for (i in 0...salted.length) {
            h = (h ^ salted.charCodeAt(i)) & 0xffffffff;
            h = (h * 16777619) & 0xffffffff;
        }
        return h & 0x7fffffff;
    }

    /** Find every `<stateName>.value` read in `e` where `stateName`
        is a primitive State field. These get lifted into function
        parameters of the synthesised wrapper so the value comes
        from the Swift-side `appState.<name>` (fresh, post-binding)
        rather than the Haxe mirror (potentially stale when Swift
        UI bindings own the write). **/
    static function collectPrimitiveStateReads(e:Expr, scope:Map<String, Bool>):Array<{name:String, type:ComplexType}> {
        var found:Array<{name:String, type:ComplexType}> = [];
        function visit(node:Expr) {
            switch (node.expr) {
                case EField({expr: EConst(CIdent(name))}, "value")
                    if (stateFieldNames.exists(name)
                        && !scope.exists(name)
                        && isPrimitiveStateInner(stateFieldTypes.get(name))
                        && !arrContains(found, name)):
                    found.push({name: name, type: stateFieldTypes.get(name)});
                case EFunction(_, _): return;
                default:
            }
            ExprTools.iter(node, visit);
        }
        visit(e);
        return found;
    }

    /** Like `qualifyStateRefs`, but ALSO lifts `<stateName>.value`
        reads (for primitive states in `primReads`) into bare
        parameter references — the synthesised wrapper carries the
        Swift-side current value as `<stateName>` parameter. **/
    static function qualifyAndLiftStateRefs(e:Expr, scope:Map<String, Bool>, primReads:Array<{name:String, type:ComplexType}>):Expr {
        function isLifted(name:String):Bool {
            return arrContains(primReads, name);
        }
        function rewrite(node:Expr):Expr {
            return switch (node.expr) {
                // Lift `state.value` → bare ident `state`.
                case EField({expr: EConst(CIdent(name)), pos: ip}, "value")
                    if (stateFieldNames.exists(name) && !scope.exists(name) && isLifted(name)):
                    {expr: EConst(CIdent(name)), pos: node.pos};
                // Qualify bare state ref (non-lifted) → ClassName.instance.X.
                case EConst(CIdent(name))
                    if (stateFieldNames.exists(name) && !scope.exists(name) && !isLifted(name)):
                    needsInstance = true;
                    var clsExpr:Expr = {expr: EConst(CIdent(className)), pos: node.pos};
                    var instExpr:Expr = {expr: EField(clsExpr, "instance"), pos: node.pos};
                    {expr: EField(instExpr, name), pos: node.pos};
                // Don't descend into nested closures.
                case EFunction(_, _): node;
                default:
                    ExprTools.map(node, rewrite);
            };
        }
        return rewrite(e);
    }

    /** Recurse into immediate children with the same scope. **/
    static function defaultRecurse(e:Expr, scope:Map<String, Bool>, frames:Array<ForEachFrame>):Expr {
        return ExprTools.map(e, child -> walk(child, scope, frames));
    }

    /** Walk the receiver chain of a modifier call. The callee for
        `x.foo` is `EField(x, "foo")`; we recurse into `x`. **/
    static function walkCallee(callee:Expr, scope:Map<String, Bool>, frames:Array<ForEachFrame>):Expr {
        return switch (callee.expr) {
            case EField(target, fieldName):
                {expr: EField(walk(target, scope, frames), fieldName), pos: callee.pos};
            default:
                walk(callee, scope, frames);
        };
    }

    static function isBridgedModifierCallee(callee:Expr, modifierMap:Map<String, String>):Bool {
        return switch (callee.expr) {
            case EField(_, fieldName): modifierMap.exists(fieldName);
            default: false;
        };
    }

    static function lookupReturnType(callee:Expr, modifierMap:Map<String, String>):String {
        return switch (callee.expr) {
            case EField(_, fieldName) if (modifierMap.exists(fieldName)): modifierMap.get(fieldName);
            default: "String";
        };
    }

    /** If the argument is simple, leave it for the existing typed
        codepath; otherwise capture it for bridging with the given
        return type. **/
    static function maybeBridge(arg:Expr, scope:Map<String, Bool>, frames:Array<ForEachFrame>, retType:String):Expr {
        if (isSimpleExpr(arg, scope)) return walk(arg, scope, frames);
        var lambdaParams = collectLambdaParams(arg, scope);
        var primReads = collectPrimitiveStateReads(arg, scope);
        var stateRefs = collectStateRefs(arg, scope);
        var arrayStateRefs = stateRefs.filter(n -> !arrContains(primReads, n));
        var qualified = qualifyAndLiftStateRefs(arg, scope, primReads);
        var hash = hashExpr(arg);
        var funcName = '_sui_expr_$hash';
        if (!synthesisedExprs.exists(funcName)) {
            synthesisedExprs.set(funcName, {
                expr: qualified,
                pos: arg.pos,
                params: lambdaParams,
                primReads: primReads,
                returnType: complexFromName(retType),
                isAction: false,
            });
        }
        var stateList = arrayStateRefs.join(",");
        var paramList = lambdaParams.join(",");
        var primList = [for (p in primReads) p.name].join(",");
        var sentinel = "\u{0001}SUIBRIDGE\u{0001}" + funcName + "\u{0001}" + stateList + "\u{0001}" + paramList + "\u{0001}" + primList;
        return {expr: EConst(CString(sentinel)), pos: arg.pos};
    }

    static function complexFromName(name:String):ComplexType {
        return switch (name) {
            case "Float": macro :Float;
            case "Int": macro :Int;
            case "Bool": macro :Bool;
            default: macro :String;
        };
    }

    /** "Simple" args that the existing typed codepath handles
        cleanly — leave them untouched. Anything outside this
        narrow set gets bridged. **/
    static function isSimpleExpr(e:Expr, scope:Map<String, Bool>):Bool {
        return switch (e.expr) {
            case EConst(CString(_) | CInt(_) | CFloat(_)): true;
            case EConst(CIdent(name)):
                name == "true" || name == "false" || name == "null"
                    || stateFieldNames.exists(name) || scope.exists(name);
            case EField(inner, "value"):
                isSimpleStateRef(inner);
            case EArray(arr, idx):
                isSimpleExpr(arr, scope) && isSimpleExpr(idx, scope);
            default: false;
        };
    }

    static function isSimpleStateRef(e:Expr):Bool {
        return switch (e.expr) {
            case EConst(CIdent(name)): stateFieldNames.exists(name);
            default: false;
        };
    }

    /** Collect identifiers in `e` that match a lambda param in
        `scope` (ForEach closure / legacy index). Order-preserving,
        de-duplicated. These become function parameters of the
        synthesised wrapper. **/
    static function collectLambdaParams(e:Expr, scope:Map<String, Bool>):Array<String> {
        var found:Array<String> = [];
        function visit(node:Expr) {
            switch (node.expr) {
                case EConst(CIdent(name)) if (scope.exists(name) && found.indexOf(name) == -1):
                    found.push(name);
                default:
            }
            ExprTools.iter(node, visit);
        }
        visit(e);
        return found;
    }

    /** Collect identifiers in `e` that reference a State field
        (not shadowed by a lambda param). The SwiftUI side touches
        each one inside a subscription closure so view re-renders
        track the state mutations the bridged Haxe expression
        reads. **/
    static function collectStateRefs(e:Expr, scope:Map<String, Bool>):Array<String> {
        var found:Array<String> = [];
        function visit(node:Expr) {
            switch (node.expr) {
                case EConst(CIdent(name)) if (stateFieldNames.exists(name) && !scope.exists(name) && found.indexOf(name) == -1):
                    found.push(name);
                case EFunction(_, _): return; // Nested closure has its own scope; ignore.
                default:
            }
            ExprTools.iter(node, visit);
        }
        visit(e);
        return found;
    }

    /** Rewrite bare `<stateName>` references → `<ClassName>.instance.<name>`.
        Leaves lambda-param refs alone (they're in scope of the
        synthesised function as parameters). **/
    static function qualifyStateRefs(e:Expr, scope:Map<String, Bool>):Expr {
        return switch (e.expr) {
            case EConst(CIdent(name))
                if ((stateFieldNames.exists(name) || instanceMemberNames.exists(name))
                    && !scope.exists(name)):
                needsInstance = true;
                var clsExpr:Expr = {expr: EConst(CIdent(className)), pos: e.pos};
                var instExpr:Expr = {expr: EField(clsExpr, "instance"), pos: e.pos};
                {expr: EField(instExpr, name), pos: e.pos};
            // DO descend into nested closures here — unlike the
            // wrapper path, the ForEach action builders need state
            // refs inside the lifted closure body qualified too
            // (the closure executes in a static context). Lambda
            // params shadow via `scope`.
            case EFunction(kind, fn):
                var newScope = copyScope(scope);
                for (a in fn.args) newScope.set(a.name, true);
                var newFn:Function = {args: fn.args, ret: fn.ret, expr: fn.expr == null ? null : qualifyStateRefs(fn.expr, newScope)};
                {expr: EFunction(kind, newFn), pos: e.pos};
            // Locals declared in a block shadow members for the
            // statements that follow.
            case EBlock(stmts):
                var blockScope = copyScope(scope);
                var newStmts:Array<Expr> = [];
                for (s in stmts) {
                    newStmts.push(qualifyStateRefs(s, blockScope));
                    switch (s.expr) {
                        case EVars(vars):
                            for (v in vars) blockScope.set(v.name, true);
                        default:
                    }
                }
                {expr: EBlock(newStmts), pos: e.pos};
            case EVars(vars):
                {expr: EVars([for (v in vars) {
                    name: v.name,
                    type: v.type,
                    expr: v.expr == null ? null : qualifyStateRefs(v.expr, scope),
                }]), pos: e.pos};
            default:
                ExprTools.map(e, child -> qualifyStateRefs(child, scope));
        };
    }

    /** True if the ComplexType is `sui.state.State<…>` (or
        unqualified `State<…>`). **/
    static function isStateType(t:Null<ComplexType>):Bool {
        return stateInnerType(t) != null;
    }

    /** Returns the inner type T of a `sui.state.State<T>` ComplexType,
        or null if `t` isn't a State field. **/
    static function stateInnerType(t:Null<ComplexType>):Null<ComplexType> {
        if (t == null) return null;
        return switch (t) {
            case TPath(p) if (p.name == "State"
                && (p.pack.length == 0
                    || (p.pack.length == 2 && p.pack[0] == "sui" && p.pack[1] == "state"))
                && p.params != null && p.params.length == 1):
                switch (p.params[0]) {
                    case TPType(inner): inner;
                    default: null;
                }
            default: null;
        };
    }

    /** Is `t` a value-typed primitive that the SwiftUI binding
        carries as a Swift property? Those get passed as parameters
        into the synthesised wrapper; everything else (Array, object,
        custom enum, …) stays on the Haxe side. **/
    static function isPrimitiveStateInner(t:Null<ComplexType>):Bool {
        if (t == null) return false;
        return switch (t) {
            case TPath(p) if (p.pack.length == 0):
                switch (p.name) {
                    case "String" | "Int" | "Float" | "Bool": true;
                    default: false;
                }
            default: false;
        };
    }

    static function arrContains(arr:Array<{name:String, type:ComplexType}>, name:String):Bool {
        for (p in arr) if (p.name == name) return true;
        return false;
    }

    static function copyScope(s:Map<String, Bool>):Map<String, Bool> {
        var copy = new Map<String, Bool>();
        for (k => v in s) copy.set(k, v);
        return copy;
    }

    /** Stable content hash over the expression's `toString`. **/
    static function hashExpr(e:Expr):String {
        var src = ExprTools.toString(e);
        var h:Int = 0x811c9dc5;
        for (i in 0...src.length) {
            h = (h ^ src.charCodeAt(i)) & 0xffffffff;
            h = (h * 16777619) & 0xffffffff;
        }
        var u = h & 0x7fffffff;
        return StringTools.hex(u, 8).toLowerCase();
    }
}

typedef SynthesisedExpr = {
    expr:Expr,
    pos:Position,
    params:Array<String>,
    ?primReads:Array<{name:String, type:ComplexType}>,
    ?returnType:ComplexType,
    ?isAction:Bool,
};

/** One enclosing ForEach level at an action call site. `param` is
    the iteration variable's name; `isIndex` is true for `byIndex` /
    legacy string form (the param is the Int index) and false for the
    closure form (the param is the array element, re-materialised by
    the builder from the iterated state array `arr`). **/
typedef ForEachFrame = {
    param:String,
    isIndex:Bool,
    arr:Null<Expr>,
    pos:Position,
};
#end
