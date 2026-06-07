import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

/**
    Exercises sui's typed-expression emission paths:

    - `Text.bind(...)` with bare state ref, mixed literal + state,
      nested `.value`, array subscript with lambda param.
    - `ForEach.byIndex(arr, i -> body)` with parallel-array
      subscripts inside the body — every reference is type-checked
      Haxe and lands as `appState.<name>[i]` in Swift.
    - Closure-form `new ForEach(arr, item -> body)` iterating
      elements.
    - Conditional bool state, action closures (plain + ForEach row
      builders), a `sheet` binding — all in bridge mode so
      `qualifyStateName` adds the `appState.` prefix at every
      emission site.

    `@:expose static noop` forces `needsRuntimeBridge = true` so
    every emitter goes through the bridge codepath; without an
    `@:expose` method the app would stay in standalone `@State`
    mode and the prefixing logic wouldn't fire.

    Run via `tests/run_tests.sh` — output is diffed against
    `expected/ContentView.swift`.
**/
class TestTypedExpressions extends App {
    static function main() {}

    public var name:State<String>;
    public var count:State<Int>;
    public var todos:State<Array<String>>;
    public var colors:State<Array<String>>;
    public var isVisible:State<Bool>;
    public var sheetOpen:State<Bool>;

    public function new() {
        super();
        appName = "TestTypedExpr";
        bundleIdentifier = "com.test.typedexpr";
        name = new State<String>("World", "name");
        count = new State<Int>(0, "count");
        todos = new State<Array<String>>(["a", "b", "c"], "todos");
        colors = new State<Array<String>>(["#ff0000", "#00ff00", "#0000ff"], "colors");
        isVisible = new State<Bool>(true, "isVisible");
        sheetOpen = new State<Bool>(false, "sheetOpen");
    }

    /** Forces bridge mode — without an @:expose method sui keeps
        the app in standalone @State and `qualifyStateName` returns
        bare names. **/
    @:expose public static function noop():String { return ""; }

    override function body():View {
        return new VStack([
            // Bare State<String> via .value
            Text.bind(name.value),
            // Mixed literal + state with Haxe single-quote interp
            Text.bind('Count: ${count.value}'),
            // Ternary on bool state
            Text.bind(isVisible.value ? "shown" : "hidden"),
            // ForEach.byIndex with parallel-array subscript + a row
            // action closure (lifted into an indexed builder — the
            // Swift side dispatches the live loop index).
            ForEach.byIndex(todos, i ->
                new HStack(null, 8, [
                    Image.systemImage("circle.fill")
                        .foregroundHex(colors.value[i]),
                    Text.bind(todos.value[i])
                ])
                    .onTapGesture(() -> count.value = i)
            ),
            // Closure form iterating elements, with a row action that
            // captures the element (re-materialised by the builder).
            new ForEach(todos, item ->
                new Text(item)
                    .onTapGesture(() -> name.value = item)
            ),
            // Button.withView: an icon-labelled button (regression
            // guard — withView used to drop its label view and emit a
            // blank Button("")).
            Button.withView(
              Image.systemImage("gear").foregroundColor(ColorValue.Secondary),
              () -> count.value = 0
            ),
            // Action closures (previously StateAction variants)
            new Button("Inc", () -> count.value++),
            new Button("Reset", () -> count.value = 0),
            new Button("Toggle", () -> isVisible.value = !isVisible.value),
        ])
            .sheet("sheetOpen", new Text("Modal"));
    }
}
