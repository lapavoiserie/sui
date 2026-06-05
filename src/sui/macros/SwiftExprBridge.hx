package sui.macros;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;

/**
    Bridges arbitrary Haxe expressions into the SwiftUI view tree by
    synthesising a uniquely-named `@:expose` Haxe function whose body
    is the user's expression, and emitting a `HaxeBridgeC.<name>(...)`
    call on the Swift side. The expression is *executed* by hxcpp at
    runtime — there is no Haxe→Swift transpilation.

    The full Haxe language is therefore available inside any modifier
    argument that this module handles. The only constraint is that
    the expression must compile in Haxe (`Reflect`, `Math`, custom
    helpers, recursive logic — all fine).

    Used by sui modifiers that previously took stringly-typed Swift
    snippets (`foregroundHex`, `backgroundHex`, …). Each call site
    is hashed into a stable identifier so identical expressions in
    different sites share one wrapper function.

    The synthesised functions are injected into the App class by
    `StateMacro.build` — that's where Haxe still lets us add fields.
**/
class SwiftExprBridge {
    /** Map from "<modifier>:<exprHash>" → synthesised function name.
        Populated by `register`, drained by `StateMacro.build` to
        emit the actual fields. **/
    public static var synthesised:Map<String, SynthesisedFunction> = new Map();

    /** Register an expression for synthesis. Returns the unique
        function name the bridge will expose. Idempotent: registering
        the same key twice returns the same name. **/
    public static function register(
        modifier:String,
        expr:Expr,
        ?lambdaParams:Array<{name:String, type:ComplexType}>
    ):String {
        var hash = hashExpr(expr);
        var key = '${modifier}:${hash}';
        if (synthesised.exists(key)) return synthesised.get(key).name;

        var name = '_sui_expr_${hash}';
        synthesised.set(key, {
            name: name,
            expr: expr,
            params: lambdaParams != null ? lambdaParams : [],
            returnType: inferReturnType(modifier),
            modifier: modifier,
        });
        return name;
    }

    /** Drained by StateMacro at the end of build(). Returns a list
        of `Field` to add to the App class. **/
    public static function drainAsFields():Array<Field> {
        var fields:Array<Field> = [];
        for (key in synthesised.keys()) {
            var s = synthesised.get(key);
            fields.push({
                name: s.name,
                access: [APublic, AStatic],
                meta: [{name: ":expose", pos: s.expr.pos}],
                kind: FFun({
                    args: [for (p in s.params) {name: p.name, type: p.type}],
                    ret: s.returnType,
                    expr: macro return $e{s.expr},
                }),
                pos: s.expr.pos,
            });
        }
        synthesised = new Map(); // drain
        return fields;
    }

    /** Stable hash for an expression. Uses `ExprTools.toString` then
        a short content-derived suffix. Deterministic across builds
        for identical source. **/
    static function hashExpr(e:Expr):String {
        var src = ExprTools.toString(e);
        // Cheap content hash — Adler-ish. Stable across runs.
        var h:Int = 0x811c9dc5;
        for (i in 0...src.length) {
            h = (h ^ src.charCodeAt(i)) & 0xffffffff;
            h = (h * 16777619) & 0xffffffff;
        }
        // Hex it. Strip sign by masking to 32-bit positive.
        var u = h & 0x7fffffff;
        return StringTools.hex(u, 8).toLowerCase();
    }

    /** What Swift return type does this modifier need? **/
    static function inferReturnType(modifier:String):ComplexType {
        return switch (modifier) {
            case "foregroundHex" | "backgroundHex": macro :String;
            case "proportionalOffset" | "proportionalFrame" |
                 "opacity" | "scaleEffect" | "rotationEffect" |
                 "offset" | "blur" | "brightness" | "contrast" |
                 "saturation" | "grayscale": macro :Float;
            default: macro :String;
        };
    }
}

typedef SynthesisedFunction = {
    name:String,
    expr:Expr,
    params:Array<{name:String, type:ComplexType}>,
    returnType:ComplexType,
    modifier:String,
}
#end
