package sui.nui;

import nui.Color as Wire;
import nui.Role;
import sui.View.ColorValue;

/**
	A colour said in `nui`'s words, and the Swift that draws one.

	`sui` resolves colours in SwiftUI, which is right: `Color.accentColor` is
	the one the person set, and the semantic colours follow light, dark and
	increased contrast without anybody asking. What was missing is that none of
	it reached the **wire** — `sui.nui.Describe` emitted no colour modifier at
	all, so a panel projected from here arrived with no colour on it.

	## A role becomes a semantic colour

	Not a number. `role:danger` is `.red`, which on Apple's platforms is not a
	fixed `#FF0000` but a colour that shifts with the display and with the
	person's accessibility settings. `role:surface` is the system background,
	`role:text` is `.primary`. That is exactly what a role crossing as a role is
	for.
**/
class Colors {
	/** A `ColorValue` in the canon's words, or null when it says nothing. **/
	public static function say(colour:Null<ColorValue>):Null<Wire> {
		if (colour == null) return null;
		return switch (colour) {
			case Primary | Accent: Wire.role(Role.Accent);
			case Secondary: Wire.role(Role.Muted);
			case Custom(hex): Wire.hex(hex);

			// Conventional components: a name resolves to nothing
			// per-platform, so it cannot cross as one. Same call `cui` and
			// `aui` make, in the same direction.
			case Red: Wire.rgb(220, 38, 38);
			case Orange: Wire.rgb(234, 88, 12);
			case Yellow: Wire.rgb(202, 138, 4);
			case Green: Wire.rgb(22, 163, 74);
			case Blue: Wire.rgb(37, 99, 235);
			case Purple: Wire.rgb(124, 58, 237);
			case Pink: Wire.rgb(219, 39, 119);
			case White: Wire.rgb(255, 255, 255);
			case Black: Wire.rgb(0, 0, 0);
			case Gray: Wire.rgb(128, 128, 128);
			// A modifier asking for nothing is not a modifier.
			case Clear: null;
		}
	}

	/**
		The SwiftUI expression for a colour the wire said.

		A role becomes a **semantic** colour, which on Apple's platforms is not
		a fixed number: `.red` shifts with the display and with increased
		contrast, and `Color.accentColor` is the one the person chose. That is
		what a role crossing as a role buys here.
	**/
	public static function swift(said:Null<String>):Null<String> {
		if (said == null) return null;

		var role = Wire.roleOf(said);
		if (role != null) return switch (role) {
			case Accent: "Color.accentColor";
			case Danger: "Color.red";
			case Warning: "Color.orange";
			case Success: "Color.green";
			// The system background, which differs by platform: the generator
			// writes whichever this build targets. `.primary`'s own backdrop.
			case Surface: "Color.primary.opacity(0.06)";
			case Text: "Color.primary";
			case Muted: "Color.secondary";
			case Border: "Color.gray.opacity(0.35)";
		}

		var parts = Wire.rgbOf(said);
		if (parts == null) return null;
		var f = (v:Int) -> Std.string(Math.round(v / 2.55) / 100);
		return "Color(.sRGB, red: " + f(parts.r) + ", green: " + f(parts.g)
			+ ", blue: " + f(parts.b) + ", opacity: " + f(parts.a) + ")";
	}
}
