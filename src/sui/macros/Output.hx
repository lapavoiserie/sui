package sui.macros;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
#end

/**
	Where this build writes, when the caller knows better than the build file.

	## The problem this exists for

	One `build-sui.hxml` serves three platforms — macOS, iOS, visionOS — and it
	names one output directory. So all three wrote their generated C++ into the
	same `build/cpp` and their Swift into the same `build/swift`, and nothing
	ever pruned either. A build left its files, the next added to them, and the
	CLI then built the static library by sweeping every `.o` it could find.

	Measured on `mui/examples` before this landed: `obj/darwinarm64` held 239
	object files while hxcpp's own `all_objs` — the list of what it actually
	linked — held 150. Among the 89 extras was `WinUISink.o`, from **`wui`**,
	because that backend's build file writes to the same `build/cpp` too. The
	contamination was not merely between one backend's platforms; it was between
	backends.

	## Why a define and not `-cpp`

	A second `-cpp` on the command line does not override the one in the build
	file — Haxe answers `Error: Multiple targets`. So the CLI cannot simply pass
	a different output directory.

	`Compiler.setOutput` can: it changes the output *directory* without touching
	the *target*, so there is nothing for Haxe to find ambiguous. That keeps
	every existing build file working untouched — the 22 examples, `mui init`'s
	template, the test harnesses that call `haxe` directly — because a build
	that does not set the define is left exactly as it was.

	## Absent means unchanged

	Deliberately not a default. If `cpp-output` is not given, the build file's
	own `-cpp` stands. This is a redirection offered to a caller that knows
	which platform it is building; it is not a policy imposed on anyone else.
**/
class Output {
	#if macro

	/**
		Honour `-D cpp-output`.

		Called from `SwiftGenerator.register()`, which every sui build file
		already loads — so the redirection needs no new line in any build file.
	**/
	public static function redirectCpp():Void {
		var dir = Context.definedValue("cpp-output");
		if (dir == null)
			return;

		// A redirection that lands somewhere the target cannot use is worth
		// refusing here rather than discovering later as a missing Build.xml.
		if (!Context.defined("cpp"))
			Context.error("-D cpp-output only means something for a C++ target, and this build is not one.\n"
				+ "  Drop the define, or build for cpp.", Context.currentPos());

		Compiler.setOutput(dir);
	}

	/** The Swift output directory: what `-D swift-output` says, else the
		historical `build/swift`. **/
	public static function swiftDir():String {
		var dir = Context.definedValue("swift-output");
		return dir == null ? "build/swift" : dir;
	}
	#end
}
