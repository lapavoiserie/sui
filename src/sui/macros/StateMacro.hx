package sui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;

/**
    Build macro for App subclasses that:
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

    The user writes plain Haxe; the macro takes care of everything.
**/
class StateMacro {
    /** Modifiers whose single argument is bridged when complex.
        Mirror in `SwiftGenerator.SUI_BRIDGE_PREFIX` dispatcher. **/
    static final BRIDGED_MODIFIERS = [
        "foregroundHex" => true,
        "backgroundHex" => true,
    ];

    static var synthesisedExprs:Map<String, SynthesisedExpr>;
    static var stateFieldNames:Map<String, Bool>;
    static var className:String;

    public static function build():Array<Field> {
        synthesisedExprs = new Map();
        stateFieldNames = new Map();
        className = {
            var cls = Context.getLocalClass();
            cls != null ? cls.get().name : "";
        };

        var fields = Context.getBuildFields();
        var stateInits:Array<Expr> = [];
        var newFields:Array<Field> = [];

        // First pass: collect every state-typed field name (both
        // `@:state var x:T` and manual `var x:State<T>`). The
        // walker uses this list to qualify bare references inside
        // bridged expressions.
        for (field in fields) {
            switch (field.kind) {
                case FVar(t, _):
                    if (isStateType(t)) stateFieldNames.set(field.name, true);
                default:
            }
        }

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

        if (stateInits.length > 0) {
            var ctorFound = false;
            for (f in newFields) {
                if (f.name == "new") {
                    ctorFound = true;
                    switch (f.kind) {
                        case FFun(func):
                            var existingBody = func.expr;
                            var allExprs:Array<Expr> = stateInits.copy();
                            if (existingBody != null) allExprs.push(existingBody);
                            func.expr = macro $b{allExprs};
                        default:
                    }
                    break;
                }
            }

            if (!ctorFound) {
                var allExprs:Array<Expr> = [macro super()];
                for (e in stateInits) allExprs.push(e);
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

        // Walk every method body, replacing bridged-modifier calls
        // with sentinel strings and synthesising wrappers.
        for (f in newFields) {
            switch (f.kind) {
                case FFun(func) if (func.expr != null):
                    func.expr = walk(func.expr, new Map());
                default:
            }
        }

        // Append the synthesised wrapper functions.
        for (entry in synthesisedExprs.keyValueIterator()) {
            var funcName = entry.key;
            var s = entry.value;
            var args:Array<FunctionArg> = [for (p in s.params) {name: p, type: macro :Int}];
            // ABI convention: always at least one parameter (the
            // String "_unused"), so the existing bridge generator
            // keeps emitting a `(_unused: String): String` shape
            // even when the expression has no lambda params.
            if (args.length == 0) {
                args.push({name: "_unused", type: macro :String});
            }
            newFields.push({
                name: funcName,
                access: [APublic, AStatic],
                meta: [{name: ":expose", pos: s.pos}],
                kind: FFun({
                    args: args,
                    ret: macro :String,
                    expr: macro return $e{s.expr},
                }),
                pos: s.pos,
            });
        }

        return newFields;
    }

    /** Walk an Expr tree, tracking lambda-param scope (from
        ForEach legacy `"i"` form and closure form), and rewrite
        every bridged-modifier call with a complex argument. **/
    static function walk(e:Expr, scope:Map<String, Bool>):Expr {
        return switch (e.expr) {
            // ForEach legacy form: ENew("ForEach", [arr, "i", body])
            case ENew(t, args) if (t.name == "ForEach" && args.length == 3):
                switch (args[1].expr) {
                    case EConst(CString(idx)):
                        var newScope = copyScope(scope);
                        newScope.set(idx, true);
                        var newArr = walk(args[0], scope);
                        var newBody = walk(args[2], newScope);
                        {expr: ENew(t, [newArr, args[1], newBody]), pos: e.pos};
                    default:
                        defaultRecurse(e, scope);
                }
            // ForEach closure form: ENew("ForEach", [arr, item -> body])
            case ENew(t, args) if (t.name == "ForEach" && args.length == 2):
                switch (args[1].expr) {
                    case EFunction(kind, fn):
                        var newScope = copyScope(scope);
                        for (a in fn.args) newScope.set(a.name, true);
                        var newArr = walk(args[0], scope);
                        var newFn:Function = {args: fn.args, ret: fn.ret, expr: walk(fn.expr, newScope)};
                        var newLambda:Expr = {expr: EFunction(kind, newFn), pos: args[1].pos};
                        {expr: ENew(t, [newArr, newLambda]), pos: e.pos};
                    default:
                        defaultRecurse(e, scope);
                }
            // Bridged modifier: <view>.foregroundHex(<arg>)
            case ECall(callee, args) if (args.length == 1 && isBridgedModifierCallee(callee)):
                var arg = args[0];
                var newReceiver = walkCallee(callee, scope);
                if (isSimpleExpr(arg, scope)) {
                    // Existing typed/stringly codepath handles it.
                    var newArg = walk(arg, scope);
                    {expr: ECall(newReceiver, [newArg]), pos: e.pos};
                } else {
                    // Capture for bridging.
                    var lambdaParams = collectLambdaParams(arg, scope);
                    var stateRefs = collectStateRefs(arg, scope);
                    var qualified = qualifyStateRefs(arg, scope);
                    var hash = hashExpr(arg);
                    var funcName = '_sui_expr_$hash';
                    if (!synthesisedExprs.exists(funcName)) {
                        synthesisedExprs.set(funcName, {
                            expr: qualified,
                            pos: arg.pos,
                            params: lambdaParams,
                        });
                    }
                    var stateList = stateRefs.join(",");
                    var paramList = lambdaParams.join(",");
                    var sentinel = "\u{0001}SUIBRIDGE\u{0001}" + funcName + "\u{0001}" + stateList + "\u{0001}" + paramList;
                    var sentinelExpr:Expr = {expr: EConst(CString(sentinel)), pos: arg.pos};
                    {expr: ECall(newReceiver, [sentinelExpr]), pos: e.pos};
                }
            // Generic recursion with scope-aware EFunction handling.
            case EFunction(kind, fn):
                var newScope = copyScope(scope);
                for (a in fn.args) newScope.set(a.name, true);
                var newFn:Function = {args: fn.args, ret: fn.ret, expr: walk(fn.expr, newScope)};
                {expr: EFunction(kind, newFn), pos: e.pos};
            default:
                defaultRecurse(e, scope);
        };
    }

    /** Recurse into immediate children with the same scope. **/
    static function defaultRecurse(e:Expr, scope:Map<String, Bool>):Expr {
        return ExprTools.map(e, child -> walk(child, scope));
    }

    /** Walk the receiver chain of a modifier call. The callee for
        `x.foo` is `EField(x, "foo")`; we recurse into `x`. **/
    static function walkCallee(callee:Expr, scope:Map<String, Bool>):Expr {
        return switch (callee.expr) {
            case EField(target, fieldName):
                {expr: EField(walk(target, scope), fieldName), pos: callee.pos};
            default:
                walk(callee, scope);
        };
    }

    static function isBridgedModifierCallee(callee:Expr):Bool {
        return switch (callee.expr) {
            case EField(_, fieldName): BRIDGED_MODIFIERS.exists(fieldName);
            default: false;
        };
    }

    /** "Simple" args that the existing typed codepath handles
        cleanly — leave them untouched. Anything outside this
        narrow set gets bridged. **/
    static function isSimpleExpr(e:Expr, scope:Map<String, Bool>):Bool {
        return switch (e.expr) {
            case EConst(CString(_)): true;
            case EConst(CIdent(name)):
                stateFieldNames.exists(name) || scope.exists(name);
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
            case EConst(CIdent(name)) if (stateFieldNames.exists(name) && !scope.exists(name)):
                var clsExpr:Expr = {expr: EConst(CIdent(className)), pos: e.pos};
                var instExpr:Expr = {expr: EField(clsExpr, "instance"), pos: e.pos};
                {expr: EField(instExpr, name), pos: e.pos};
            // Don't descend into nested closures (they have their own scope).
            case EFunction(_, _): e;
            default:
                ExprTools.map(e, child -> qualifyStateRefs(child, scope));
        };
    }

    /** True if the ComplexType is `sui.state.State<…>` (or
        unqualified `State<…>`). **/
    static function isStateType(t:Null<ComplexType>):Bool {
        if (t == null) return false;
        return switch (t) {
            case TPath(p):
                p.name == "State" && (p.pack.length == 0
                    || (p.pack.length == 2 && p.pack[0] == "sui" && p.pack[1] == "state"));
            default: false;
        };
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
};
#end
