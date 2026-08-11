package sui.ui;

import sui.View;

/**
    Conditionally renders one of two views based on a boolean state variable.
    Maps to SwiftUI's `if/else` in a `@ViewBuilder`.

    Boolean condition (typed State ref or string):
    ```haxe
    new ConditionalView(isLoggedIn, buildMainView(), buildLoginView())
    ```

    Generates:
    ```swift
    if appState.isLoggedIn {
        // true branch
    } else {
        // false branch
    }
    ```

    String equality condition (typed State ref or string):
    ```haxe
    new ConditionalView(currentScreen, "login", buildLoginView(), buildDefaultView())
    ```

    Generates:
    ```swift
    if appState.currentScreen == "login" {
        // match branch
    } else {
        // else branch
    }
    ```
**/
class ConditionalView extends View {
    /**
        The condition: a `State<Bool>` to read, or the name of one.

        Typed `Dynamic` because it holds either, and because a `String` field
        cannot hold a `State` on a static target. It could on the JVM and under
        `--interp`, which is why the tests were green while the condition
        rendered nothing at all on a device: the value went in and came back
        null, so neither branch was taken and the line simply was not there.
    **/
    public var stateName:Dynamic;
    public var matchValue:String;
    public var trueView:View;
    public var falseView:View;

    /** Boolean condition: show trueView when state is true, falseView otherwise.
        Accepts a State<T> field reference or a string name. **/
    public function new(stateName:Dynamic, trueView:View, ?falseView:View) {
        super();
        this.viewType = "ConditionalView";
        this.stateName = stateName;
        this.trueView = trueView;
        this.falseView = falseView;
    }
}
