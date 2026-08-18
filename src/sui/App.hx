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
    /**
        What this application owns for as long as it runs.

        An effect an application starts — watching connectivity, a subscription,
        a timer — has to be stopped, and there is exactly one moment every
        backend agrees on: the application is over.

            lifetime.own(new Effect(() -> { … Effect.onCleanup(stop); }).dispose);

        **A view lifetime exists too**, through `lifetime.keep(key, start)`: it
        lasts as long as `body()` keeps declaring that key. Not as long as the
        view is on screen — those differ, and the difference is deliberate. See
        `rui.Lifetime.keep`.
       **/
    public final lifetime = new rui.Lifetime();

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
