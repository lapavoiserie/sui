import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

/**
    Test app used by the test harness to verify Swift generation.
    The actual assertions happen in tests/run_tests.sh by comparing
    generated Swift output against expected files.
**/
class TestSwiftGen extends App {
    static function main() {}

    @:state var count:Int = 0;

    public function new() {
        super();
        appName = "TestApp";
        bundleIdentifier = "com.test.app";
    }

    override function body():View {
        return new VStack([
            new Text("Hello")
                .font(FontStyle.LargeTitle)
                .padding(),
            Text.bind('Value: ${count.value}')
                .bold(),
            new HStack(null, 10, [
                new Button("-", null, count.dec(1)),
                new Button("+", null, count.inc(1))
            ]),
            new Spacer()
        ]);
    }
}
