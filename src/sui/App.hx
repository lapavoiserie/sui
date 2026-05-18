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

    /** Override to attach top-level menus to the macOS menu bar. The
        returned array is read at compile time by the SwiftGenerator
        macro and emitted as a `.commands { CommandMenu(…) { … } … }`
        modifier on the App's WindowGroup. iOS / iPadOS / tvOS
        ignore the commands at runtime (the menu bar isn't shown).

        Each item inside a `CommandMenu` is typically a `Button` with
        a `.keyboardShortcut`. See `sui.ui.CommandMenu` for a full
        example.
    **/
    public function commands():Array<sui.ui.CommandMenu> {
        return [];
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
