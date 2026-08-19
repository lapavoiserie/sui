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

	// The legacy method, transpiler-era: on the dynamic path its emission
	// referenced files the CLI overwrites or deletes. The gate under test.
	override function settings():View {
		return new Text("legacy");
	}
}
