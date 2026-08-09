import sui.App;
import sui.View;
import sui.state.State;
import sui.ui.*;

/**
    Minimal example of sui's **dynamic renderer**.

    Build with `sui build macos --watch`: instead of generating static Swift for
    this view, sui walks the Haxe tree that `body()` returns at *runtime*
    through the C `ViewNode` bridge, and `DynamicView.swift` rebuilds SwiftUI
    from it recursively.

    Two things are on show, and the second is the one that used to be missing:

    - **Actions reach Haxe.** A tap invokes the closure sitting on the live tree
      directly — no id indirection, since the tree is a GC root.
    - **A state write reaches the screen.** `taps.set(...)` notifies the C
      bridge, which rebuilds the tree and tells the host; the label follows. A
      dynamic app used to draw its first frame and then stay frozen, because the
      only thing that could rebuild it was a poll delegate that an app with a
      fixed `body()` never registers.

    This is the same runtime-dynamic mechanism a protocol renderer uses; see
    rsx2ui's `renderers/sui` for a full A2UI renderer built on it.
**/
class DynamicHello extends App {
    static function main() {}

    var taps:State<Int>;

    public function new() {
        super();
        appName = "DynamicHello";
        bundleIdentifier = "com.sui.dynamichello";
        taps = new State<Int>(0, "taps");
    }

    override function body():View {
        return new VStack(null, 16, [
            new Text("sui — dynamic renderer")
                .font(FontStyle.LargeTitle)
                .padding(),
            new Text("The Haxe view tree is rendered at runtime, through the ViewNode bridge.")
                .padding(),

            // Read at body() time. body() re-runs on every state write, so this
            // is the new value each time -- no binding to declare.
            new Text("taps: " + taps.get()),

            new Button("Tap me", () -> taps.set(taps.get() + 1)).padding(),
        ]);
    }
}
