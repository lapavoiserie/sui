package sui.mui;

/**
	Hands a sampled Glance surface to the native side, which stores it where
	the widget extension can read it.

	## Why a C symbol and not a callback

	The other direction — Swift asking Haxe for the view tree — is what
	`ViewNodeBridgeC` exists for, and Swift registering callbacks into Haxe is
	how state changes travel back. This one goes the other way at a moment
	Swift is not driving, so it is a plain `extern "C"` call into a function
	the generated Swift exports with `@_cdecl`, resolved at the final link
	like any other symbol in the app binary. It is the arrangement `wui` uses
	for its whole node runtime.

	The shim is emitted for **every** sui application, and does nothing when
	there is no widget. That is deliberate: this class is compiled into every
	app that touches `mui.surface.Resample`, and a symbol that existed only
	for widget-declaring apps would turn a missing feature into a link error.
**/
@:keep
@:cppFileCode('#include <dlfcn.h>\ntypedef void (*sui_glance_publish_fn)(const char*);')
class GlancePublish {
	/**
		Take a new sample of the running application and publish it.

		Called from the generated C entry `sui_glance_resample`, which the
		scene-phase observer in App.swift reaches when the application leaves
		the foreground. Nothing here knows which application: the bridge kept
		the one it last sampled, and on this backend there is only ever one.
	**/
	@:keep public static function resampleAndPublish():Void {
		var json = sui.mui.GlanceBridge.sampleAgain();
		if (json != null) publish(json);
	}

	/**
		Hand the snapshot to the native side, if there is one to hand it to.

		The symbol is looked up at RUNTIME rather than linked, and that is
		not fussiness. This class is compiled into every application that
		touches `mui.surface.Resample`, including the plain Haxe executable a
		macOS build links **before Xcode ever sees it** — a link with no Swift
		in it at all, which an ordinary reference fails. A weak declaration
		does not save it either: on Darwin `weak` marks a definition, and an
		undefined weak reference still has to resolve. `dlsym(RTLD_DEFAULT)`
		asks the process, at the moment it matters, whether anyone published
		that function — which is exactly the question.
	**/
	public static function publish(json:String):Void {
		#if cpp
		untyped __cpp__("{ static sui_glance_publish_fn fn = (sui_glance_publish_fn)dlsym(RTLD_DEFAULT, \"sui_glance_publish\"); if (fn) fn({0}.utf8_str()); }", json);
		#end
	}
}
