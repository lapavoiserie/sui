package sui.mui;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

/**
	`sui`'s conformance for `mui.ui.ForEach`.

	The only one of the six that is more than a line, because `sui` has two
	`ForEach` shapes and which one to emit depends on the render path. Moved here
	whole from `mui.macros.ForEachMacro`, where it used to sit beside five others
	that had nothing to do with it.
**/
class ForEach {
	/** Build a list of views, one per item. **/
	public static macro function build(items:Expr, builder:Expr):Expr {
		return transformSui(items, builder);
	}

#if macro
	/**
		`sui` has two `ForEach` shapes, and which one to emit depends on the
		render path.

		The closure form is a value: the builder runs, and the renderer walks
		what it produced. The legacy form is a *string template* the transpiler
		resolved against the generated `appState` — which is why it is the only
		one the static path understands, and why the dynamic renderer cannot
		resolve it at all: at runtime `"{items[i]}"` is a name with nothing to
		look it up in, so it yields no rows.

		sui's transpiler is decommissioned, so the closure form is what mui
		emits; the template form is kept for a build that asked for the other
		path by name.
	**/
	static function transformSui(items:Expr, builder:Expr):Expr {
		if (!Context.defined("sui_static")) {
			return macro new sui.ui.ForEach($items, $builder);
		}
		return transformSuiTemplate(items, builder);
	}

	static function transformSuiTemplate(items:Expr, builder:Expr):Expr {
		// Extract field name from items (e.g., `todos` → "todos")
		var arrayName = extractIdent(items);
		if (arrayName == null) {
			Context.error("ForEach.build: first argument must be a state field identifier", items.pos);
			return macro null;
		}

		// Extract lambda param name and body
		var paramName:String = null;
		var body:Expr = null;

		switch (builder.expr) {
			case EFunction(_, f):
				if (f.args.length > 0) paramName = f.args[0].name;
				body = f.expr;
			default:
				Context.error("ForEach.build: second argument must be a function (item -> view)", builder.pos);
				return macro null;
		}

		if (paramName == null || body == null) {
			Context.error("ForEach.build: invalid builder function", builder.pos);
			return macro null;
		}

		var indexVar = "_i";

		// Transform the body: replace param references with string templates,
		// convert Text constructors that reference the param to Text.withState
		var transformedBody = transformSuiExpr(body, paramName, arrayName, indexVar);

		// Build: new sui.ui.ForEach(arrayName, indexVar, transformedBody)
		var arrayNameExpr = macro $v{arrayName};
		var indexVarExpr = macro $v{indexVar};
		return macro new sui.ui.ForEach($arrayNameExpr, $indexVarExpr, $transformedBody);
	}

	/**
		Recursively walk an expression, replacing references to `paramName`
		with SUI string template references for the SwiftGenerator.
	**/
	static function transformSuiExpr(e:Expr, paramName:String, arrayName:String, indexVar:String):Expr {
		switch (e.expr) {
			// Return statement: transform the inner expression
			case EReturn(inner):
				if (inner != null)
					return {expr: EReturn(transformSuiExpr(inner, paramName, arrayName, indexVar)), pos: e.pos};
				return e;

			// new Text(item) or new Text(item.field) → Text.withState(template)
			case ENew(tp, args) if (tp.name == "Text" && args.length == 1):
				var template = exprToTemplate(args[0], paramName, arrayName, indexVar);
				if (template != null) {
					// Convert to sui.ui.Text.withState(template)
					var templateExpr = macro $v{template};
					return macro sui.ui.Text.withState($templateExpr);
				}
				// No param reference in the Text arg — leave as-is but recurse
				return {expr: ENew(tp, [for (a in args) transformSuiExpr(a, paramName, arrayName, indexVar)]), pos: e.pos};

			// new SomeView(args) → recurse into args
			case ENew(tp, args):
				return {expr: ENew(tp, [for (a in args) transformSuiExpr(a, paramName, arrayName, indexVar)]), pos: e.pos};

			// Array literal [a, b, c] → recurse into elements
			case EArrayDecl(values):
				return {expr: EArrayDecl([for (v in values) transformSuiExpr(v, paramName, arrayName, indexVar)]), pos: e.pos};

			// Block { expr1; expr2; } → recurse
			case EBlock(exprs):
				return {expr: EBlock([for (ex in exprs) transformSuiExpr(ex, paramName, arrayName, indexVar)]), pos: e.pos};

			// Function call f(args) → recurse into args
			case ECall(callee, args):
				return {expr: ECall(
					transformSuiExpr(callee, paramName, arrayName, indexVar),
					[for (a in args) transformSuiExpr(a, paramName, arrayName, indexVar)]
				), pos: e.pos};

			default:
				return e;
		}
	}

	/**
		Try to convert an expression to a SUI template string.
		Returns null if the expression doesn't reference paramName.

		Examples:
			item		   → "{arrayName[_i]}"
			item.title	 → "{arrayName[_i].title}"
			"Hello, " + item.name → not handled (returns null, left as-is)
	**/
	static function exprToTemplate(e:Expr, paramName:String, arrayName:String, indexVar:String):String {
		switch (e.expr) {
			// Direct reference: item → {arrayName[_i]}
			case EConst(CIdent(name)) if (name == paramName):
				return '{$arrayName[$indexVar]}';

			// Field access: item.title → {arrayName[_i].title}
			case EField(inner, field):
				switch (inner.expr) {
					case EConst(CIdent(name)) if (name == paramName):
						return '{$arrayName[$indexVar].$field}';
					default:
				}

			default:
		}
		return null;
	}

	/**
		Extract a simple identifier name from an expression.
		`todos` → "todos", `this.todos` → "todos"
	**/
	static function extractIdent(e:Expr):String {
		switch (e.expr) {
			case EConst(CIdent(name)):
				return name;
			case EField(_, field):
				return field;
			default:
				return null;
		}
	}
#end
}
