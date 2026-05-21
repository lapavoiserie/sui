import sui.App;
import sui.View;
import sui.ui.*;

class CounterApp extends App {
    static function main() {}

    @:state var count:Int = 0;

    public function new() {
        super();
        appName = "Counter";
        bundleIdentifier = "com.sui.counter";
    }

    override function body():View {
        return new VStack([
            Text.bind('Count: ${count.value}')
                .font(FontStyle.Title)
                .padding(),
            new HStack(null, 20, [
                new Button("-", null, count.dec(1)),
                new Button("+", null, count.inc(1))
            ])
        ]);
    }
}
