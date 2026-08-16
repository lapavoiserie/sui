package sui.kui;

/**
	Which Apple platform a `sui` build is for, told to `kui`.

	Called once from the build file:

	```
	--macro sui.kui.Platform.registerWithKui()
	```

	`sui` covers three, chosen by its own defines — `sui_macos`, `sui_ios`,
	`sui_visionos` — which its CLI passes on the command line. Mapping those to a
	platform is `sui`'s knowledge, and `kui` is handed a name rather than
	knowledge, so the backend states it. That is the shape
	`mui.macros.Backend.register` already takes, for the same reason: a macro
	cannot call a function it was only given the name of.

	## Two toolchains, not one

	Every `sui` build links through **Xcode**, and hxcpp compiles the Haxe half
	into a static library along the way. A capability that carries C or
	Objective-C++ therefore declares an `hxcpp` payload, and one that carries
	Swift, a framework or a Swift Package declares an `xcode` one. Both are read.

	That is why `kui.build.Payload` is keyed by toolchain rather than by platform:
	macOS is reached through hxcpp under `pui` and through Xcode here, and the
	same operating system needs two different things said about it.

	## The defines are read, not compiled against

	`#if sui_ios` inside this function would be evaluated in the **macro**
	context, where the target's defines do not exist — every branch false, nothing
	registered, and code that looks right. `Context.defined` asks the same
	question in the only way that works here.
**/
class Platform {
	/** Hand `kui` the platform and the link steps this build has. **/
	public static function registerWithKui():Void {
		#if macro
		var platform = if (haxe.macro.Context.defined("sui_ios")) "ios"
			else if (haxe.macro.Context.defined("sui_visionos")) "visionos"
			else "macos";

		kui.macros.Host.register({
			platform: platform,
			toolchains: ["hxcpp", "xcode"],
			backend: "sui",
		});
		#end
	}
}
