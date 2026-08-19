import sui.App;
import sui.View;
import sui.ui.Text;
import sui.ui.VStack;

/**
	An app that declares a Preferences surface — the shape the dynamic path's
	Settings scene is generated from — and also overrides the legacy
	`settings()`, which used to break every dynamic build that did so. The
	paths harness asserts the emitted App.swift renders the declaration
	(DynamicSurfaceView) and references none of the static-path artifacts
	(SettingsView, AppState.shared).
**/
class SurfaceFixture extends App {
	static function main() {}

	public function new() {
		super();
		appName = "SurfaceFixture";
		bundleIdentifier = "com.sui.surfacefixture";
	}

	override function body():View {
		return new VStack(null, 8, [new Text("hello")]);
	}

	@:surface(Preferences)
	function prefs():View {
		return new VStack(null, 8, [new Text("settings")]);
	}

	// The generator only reads the metadata — the return type is the mui
	// macro's business, and this fixture deliberately compiles without mui.
	@:surface(Commands)
	function shortcuts():Array<String> {
		return [];
	}

	// An Auxiliary declaration: the emission must produce a macOS Window
	// scene named after the method and rendering the root by that id.
	@:surface(Auxiliary)
	function inspector():View {
		return new Text("inspector");
	}

	// The legacy method, transpiler-era: on the dynamic path its emission
	// referenced files the CLI overwrites or deletes. The gate under test.
	override function settings():View {
		return new Text("legacy");
	}
}
