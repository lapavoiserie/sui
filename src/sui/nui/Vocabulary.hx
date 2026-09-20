package sui.nui;

#if macro
import haxe.macro.Context;
import nui.macros.Declarations;
import nui.macros.Declarations.Action;
import nui.macros.Declarations.Dialect;
import nui.macros.Declarations.Prop;
#end

/**
	What `sui` describes, read from the controls themselves.

	The reading lives in `nui.macros.Declarations`, shared by every backend.
	Two things are `sui`'s own beyond which controls and what a view is:

	- its cells are known by **name**. State lives on the Swift side and is
	  reached through a registry, so a control holds a `String` and not a cell.
	  The type therefore cannot say what the value is, and `@:cell` does.
	- it **describes only**. SwiftUI draws; nothing here ever makes a control
	  out of a node.
**/
class Vocabulary {
	/** Kept so the class exists outside macro context. **/
	public static var DUMMY(default, never):Int = 0;

	#if macro
	public static final DIALECT:Dialect = {
		pack: "sui.ui",
		view: "sui.View",
		named: "sui.nui.Describe",
		appendChildren: "sui.nui.Describe.appendChildren",
	};

	public static function types():Map<String, String>
		return Declarations.types(DIALECT);

	public static function propsFor(type:String):Array<Prop>
		return Declarations.propsFor(DIALECT, type);

	public static function actionsFor(type:String):Array<Action>
		return Declarations.actionsFor(DIALECT, type);

	public static function verify():Int
		return Declarations.verify(DIALECT);

	/** Hand `mui` the schema `ui(<VStack>…)` checks a tag against. **/
	#if (mui || mui_backend)
	public static function registerWithMui():Void {
		mui.macros.Backend.register({
			knows: type -> types().exists(type),
			keysOf: keysOf,
			requiredOf: requiredOf,
			kindOf: attributeKind,
			types: () -> [for (type in types().keys()) type],
			// Markup becomes `new sui.ui.VStack(...)` rather than a node --
			// which this backend could not have read back anyway: it reads a
			// received tree natively and never copies one into views.
			//
			// Its two-way controls hold a NAME, not a cell, so markup carries
			// the cell itself -- `<Toggle isOn={lit_}/>` -- and
			// `Describe.nameOf` turns it into the name. There is no callback
			// to give: writes go back through the Swift binding.
			//
			// Behind `-D mui_views` while the two shapes coexist.
			#if mui_views
			viewOf: (tag, given, children, pos) ->
				nui.macros.Construct.expr(DIALECT, tag, given, children, pos),
			// The canon's nine onto this backend's chain. What SwiftUI has no
			// equivalent for -- the colours among them, and the reason is not
			// obvious -- is said out loud. See `sui.nui.Decorate`.
			decorate: (view, modifiers, pos) -> macro sui.nui.Decorate.apply($view,
				[for (__m in ($modifiers : Array<Null<nui.Modifier>>)) if (__m != null) __m]),
			// What this backend can actually draw on a view. Markup refuses
			// anything else BY NAME while compiling: a decoration it cannot
			// honour is knowable here, and this project's rule is that
			// something knowable is a compile error rather than a marker or a
			// line in a log. See `mui.macros.Backend.Vocabulary.honoured`.
			honoured: () -> [
				nui.Modifiers.PADDING, nui.Modifiers.OPACITY, nui.Modifiers.CLIP,
				nui.Modifiers.WIDTH, nui.Modifiers.HEIGHT,
			],
			#end
		});
	}
	#else
	public static function registerWithMui():Void {
		Context.error("sui.nui.Vocabulary.registerWithMui() was called, but `mui` is "
			+ "not visible from this build.\n"
			+ "  Add `-lib mui`, or `-D mui_backend=sui` if mui is on the class path "
			+ "some other way.", Context.currentPos());
	}
	#end

	/** Every attribute a tag accepts: its properties and its acts. **/
	public static function keysOf(type:String):Array<String> {
		var out = [for (p in propsFor(type)) p.name];
		for (p in propsFor(type)) if (p.callback != null) out.push(p.callback);
		for (a in actionsFor(type)) out.push(a.name);
		return out;
	}

	/** The attributes a tag cannot be written without. **/
	public static function requiredOf(type:String):Array<String>
		return [for (p in propsFor(type)) if (p.argument != null && !p.optional) p.name];

	/** Which `nui.PropValue` constructor an attribute takes. `null` if unknown. **/
	public static function attributeKind(type:String, key:String):Null<String> {
		for (p in propsFor(type)) {
			if (p.name == key) return "K" + p.kind;
			if (p.callback == key) return "KCallback" + p.kind;
		}
		for (a in actionsFor(type))
			if (a.name == key) return a.carries == null ? "KCallback" : "KCallback" + a.carries;
		return null;
	}
	#end
}
