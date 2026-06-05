import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

class NormalApp extends App {
    static function main() {}

    var data:State<String>;
    var status:State<String>;

    public function new() {
        super();
        appName = "NormalHaxe";
        bundleIdentifier = "com.sui.normalhaxe";
        data = new State<String>("Loading on appear...", "data");
        status = new State<String>("", "status");
    }

    function onFetch():Void {
        data.set("Loading...");
        var http = new haxe.Http("https://example.com");
        http.onData = function(d:String) {
            data.set(d.substr(0, 200));
        };
        http.onError = function(e:String) {
            data.set("Error: " + e);
        };
        http.request(false);
    }

    function onHello():Void {
        data.set("Hello from Haxe! Time: " + Date.now().toString());
    }

    override function body():View {
        return new VStack(null, 20, [
            Text.bind(status.value)
                .font(FontStyle.Caption)
                .foregroundColor(ColorValue.Secondary),
            Text.bind(data.value)
                .font(FontStyle.Title)
                .padding(),
            new Button("Fetch example.com", onFetch),
            new Button("Say hello", onHello)
        ])
        .task(() -> {
            status.set("Fetching on appear...");
            var http = new haxe.Http("https://example.com");
            http.onData = function(d:String) {
                data.set(d.substr(0, 300));
                status.set("Loaded on appear!");
            };
            http.onError = function(e:String) {
                data.set("Error: " + e);
                status.set("Failed on appear");
            };
            http.request(false);
        })
        .onDisappear(() -> {
            trace("View disappeared");
        });
    }
}
