import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

/**
    Demonstrates the closure form of `ForEach`.

    The iteration variable is a real Haxe value bound by the lambda,
    so references to it inside child views are checked by the Haxe
    compiler and compiled to the matching Swift expression — no more
    `"name[i]"` strings hand-spliced into modifiers.
**/
class ClosureForEachApp extends App {
    static function main() {}

    @:state var colors:Array<String> = ["red", "green", "blue", "yellow"];
    @:state var selected:String = "red";

    public function new() {
        super();
        appName = "ClosureForEach";
        bundleIdentifier = "com.sui.closureforeach";
    }

    override function body():View {
        return new VStack([
            new Text("Closure-form ForEach demo")
                .font(FontStyle.Title)
                .padding(),

            // Closure form: `color` is a Haxe-typed iteration variable.
            // Inside the body, `new Text(color)` becomes
            //   Text("\(appState.colors[color])")
            // and `.tag(color)` becomes
            //   .tag(appState.colors[color])
            new Picker("Pick a color", "selected", [
                new ForEach(colors, color ->
                    new Text(color).tag(color)
                )
            ]),

            new Spacer()
        ]).padding();
    }
}
