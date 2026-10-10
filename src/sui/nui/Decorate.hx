package sui.nui;

import sui.View;

/**
	Put the canon's decorations on one of this backend's own views.

	`mui`'s markup builds `sui` controls directly (`nui.macros.Construct`), so
	its decorations arrive as the same `Array<nui.Modifier>` the node path
	would have carried — same names, same order, because the order IS the
	semantics.

	## The colours, as roles

	A canon colour is a role or its components. A role becomes
	`ColorValue.Role` and stays one until `DynamicView.swift` draws it, which
	resolves it to Apple's semantic colour (`.red` for danger, the window's
	own background for surface…) so it follows dark mode and increased
	contrast; `accent` is the application's accent when it set one
	(`ViewNodeBridge.setAccent`), else the person's. A component colour is
	`Custom` and drawn as itself. `backgroundColor` keeps its radius and
	`border` its width and radius: `Fill` and `Stroke`, neither of which clips.

	`flex` is skipped for a different reason: SwiftUI shares leftover space
	with spacers and layout priority, not with a share on the child, and
	mapping a share onto `frame(maxWidth: .infinity)` would mean something
	else.
**/
class Decorate {
	/** A canon colour word -- `role:danger` or `#c8323c` -- as this backend's own. **/
	static function colourOf(strings:Null<Array<String>>):Null<sui.View.ColorValue> {
		if (strings == null || strings.length == 0 || strings[0] == null) return null;
		var said = strings[0];
		var role = nui.Color.roleOf(said);
		if (role != null) return sui.View.ColorValue.Role((role : String));
		var hex = nui.Color.hex(said);
		return hex == null ? null : sui.View.ColorValue.Custom((hex : String));
	}

	public static function apply(view:View, modifiers:Array<nui.Modifier>):View {
		if (view == null || modifiers == null) return view;
		for (m in modifiers) {
			if (m == null) continue;
			var f = m.floats;
			switch (m.type) {
				case nui.Modifiers.PADDING:
					// One float is every edge; SwiftUI's edge insets are not
					// exposed here, so the first is taken.
					if (f != null && f.length > 0) view.padding(f[0]);

				// The canon's colours: a role stays a role (`ColorValue.Role`)
				// and is resolved by the renderer against Apple's semantic
				// colours; a component colour is drawn as itself.
				case nui.Modifiers.FOREGROUND_COLOR:
					var c = colourOf(m.strings);
					if (c != null) view.foregroundColor(c);

				case nui.Modifiers.BACKGROUND_COLOR:
					var c = colourOf(m.strings);
					var radius = (f != null && f.length > 0) ? f[0] : 0.0;
					if (c != null) view.modifierChain.push(sui.modifiers.ViewModifier.Fill(c, radius));

				case nui.Modifiers.BORDER:
					var c = colourOf(m.strings);
					var width = (f != null && f.length > 0) ? f[0] : 1.0;
					var radius = (f != null && f.length > 1) ? f[1] : 0.0;
					if (c != null) view.modifierChain.push(sui.modifiers.ViewModifier.Stroke(c, width, radius));

				case nui.Modifiers.OPACITY:
					if (f != null && f.length > 0) view.opacity(f[0]);

				case nui.Modifiers.CLIP:
					view.clip();

				case nui.Modifiers.WIDTH:
					if (f != null && f.length > 0) view.frame(f[0], null);

				case nui.Modifiers.HEIGHT:
					if (f != null && f.length > 0) view.frame(null, f[0]);

				case other:
					// Unreachable from markup: `Vocabulary.honoured` lists what
					// this can draw, and `mui`'s markup refuses anything else by
					// name while compiling. Reaching it means those two lists
					// disagree, which is a bug and not a decoration to skip.
					throw "sui.nui.Decorate: asked for \"" + other + "\", which "
						+ "Vocabulary.honoured does not list";
			}
		}
		return view;
	}
}
