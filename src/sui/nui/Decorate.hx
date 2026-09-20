package sui.nui;

import sui.View;

/**
	Put the canon's decorations on one of this backend's own views.

	`mui`'s markup builds `sui` controls directly (`nui.macros.Construct`), so
	its decorations arrive as the same `Array<nui.Modifier>` the node path
	would have carried — same names, same order, because the order IS the
	semantics.

	## The colours cannot cross, and that is worth naming

	`ViewModifier.ForegroundColor` and `Background` take a `ColorValue`, and
	this backend converts only the other way: `sui.nui.Colors.say` turns one
	into the canon's word, and `swift` turns a word into a **Swift
	expression** — which is what a RECEIVED tree needs and no use at all to a
	view built here.

	So a role written in markup has no door into a `sui` view today. It is
	traced rather than dropped: a colour that is written, carried and drawn
	nowhere is the defect this family keeps finding, and the one thing worse
	than not honouring it is not saying so.

	`flex` is skipped for a different reason: SwiftUI shares leftover space
	with spacers and layout priority, not with a share on the child, and
	mapping a share onto `frame(maxWidth: .infinity)` would mean something
	else.
**/
class Decorate {
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

				case nui.Modifiers.OPACITY:
					if (f != null && f.length > 0) view.opacity(f[0]);

				case nui.Modifiers.CLIP:
					view.clip();

				case nui.Modifiers.WIDTH:
					if (f != null && f.length > 0) view.frame(f[0], null);

				case nui.Modifiers.HEIGHT:
					if (f != null && f.length > 0) view.frame(null, f[0]);

				case other:
					trace("sui.nui.Decorate: no SwiftUI equivalent for " + other);
			}
		}
		return view;
	}
}
