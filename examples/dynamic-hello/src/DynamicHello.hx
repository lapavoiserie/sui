import sui.App;
import sui.View;
import sui.ui.*;

/**
    Minimal example of sui's **dynamic renderer**.

    Build with `sui build --watch macos`: instead of generating static Swift for
    this view, sui walks the Haxe tree that `body()` returns at *runtime* through
    the C `ViewNode` bridge, and `DynamicView.swift` rebuilds SwiftUI from it
    recursively. The Button exercises the action path — a SwiftUI tap invokes the
    Haxe closure directly through the live tree, so the click is observable on
    stdout (and mutates `taps`, proving the closure captured `this`).

    This is the same runtime-dynamic mechanism a protocol renderer uses; see
    rsx2ui's `renderers/sui` for a full A2UI renderer built on it.
**/
class DynamicHello extends App {
    static function main() {}

    var taps:Int = 0;

    public function new() {
        super();
        appName = "DynamicHello";
        bundleIdentifier = "com.sui.dynamichello";
    }

    override function body():View {
        return new VStack(null, 16, [
            new Text("sui — renderer dynamique")
                .font(FontStyle.LargeTitle)
                .padding(),
            new Text("Le view tree Haxe est rendu à l'exécution via le pont ViewNode.")
                .padding(),
            new Button("Clique-moi", () -> {
                taps++;
                Sys.println('[dynamic-hello] action Haxe déclenchée (tap #$taps)');
            }).padding(),
        ]);
    }
}
