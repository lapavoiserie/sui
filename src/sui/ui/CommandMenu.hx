package sui.ui;

import sui.View;

/**
    A top-level macOS menu-bar menu — appears next to File / Edit / View
    / Help in the system menu bar. Maps to SwiftUI's `CommandMenu` and
    is attached to the App scene via the `commands()` override.

    Items are typically `Button`s (with `.keyboardShortcut(...)` so each
    has an associated ⌘-shortcut) and `Divider`s between groups.
    Nested `Menu`s aren't supported by `CommandMenu` directly — use
    sub-`CommandMenu`s instead.

    ```haxe
    class MyApp extends sui.App {
        override function commands():Array<CommandMenu> {
            return [
                new CommandMenu("Calendar", [
                    new Button("New Event", null, newEventAction)
                        .keyboardShortcut("n", ["command"]),
                    new Button("Today", null, showTodayAction)
                        .keyboardShortcut("t", ["command"]),
                ]),
            ];
        }
    }
    ```

    On iOS / iPadOS / tvOS the menu bar isn't shown, so `CommandMenu`s
    are silently dropped by SwiftUI on those platforms.
**/
@:swiftView("CommandMenu")
class CommandMenu extends View {
    public var label:String;

    public function new(@:swiftLabel("_") label:String, content:Array<View>) {
        super();
        this.viewType = "CommandMenu";
        this.label = label;
        this.children = content;
    }
}
