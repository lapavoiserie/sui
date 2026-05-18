package sui;

/**
    Base class for a Sui application.
    Extend this class and override `body()` to define your app's root view.

    Example:
    ```haxe
    class MyApp extends sui.App {
        override function body():View {
            return new Text("Hello from Haxe!");
        }
    }
    ```
**/
@:autoBuild(sui.macros.StateMacro.build())
class App {
    public var appName:String;
    public var bundleIdentifier:String;

    public function new() {
        appName = "HaxeApp";
        bundleIdentifier = "com.haxe.app";
    }

    /** Override to define the app's root view hierarchy. **/
    public function body():View {
        return new View();
    }

    /** Override to declare a Settings (Preferences) window — the
        standard macOS `App ▸ Preferences…` / ⌘, scene. The returned
        view is rendered into its own SwiftUI `Settings` scene
        alongside the main WindowGroup; if this is left at the
        default (a bare `View()`), no Settings scene is emitted.

        ```haxe
        override function settings():View {
            return new Form([
                new Toggle("Dark Mode", "darkMode"),
                new Picker("Default View", "defaultView", [...]),
            ]);
        }
        ```

        iOS / iPadOS / tvOS ignore the Settings scene at runtime —
        on those platforms preferences belong in the system Settings
        bundle or an in-app view. **/
    public function settings():View {
        return new View();
    }

    /** Override to configure scenes (multi-window on macOS, visionOS). **/
    public function scenes():Array<Scene> {
        return [Scene.WindowGroup(appName, body)];
    }

    /** Called by the build pipeline to generate the app. Not for user code. **/
    public static function main() {
        // Entry point for hxcpp compilation.
        // The actual app launch is handled by the generated Swift @main struct.
    }
}

enum Scene {
    WindowGroup(title:String, content:() -> View);
    DocumentGroup(contentType:String, content:() -> View);
    Settings(content:() -> View);
}
