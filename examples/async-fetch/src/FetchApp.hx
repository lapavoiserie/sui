import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class FetchApp extends App {
	static function main() {}

	var result:State<String>;

	public function new() {
		super();
		appName = "AsyncFetch";
		bundleIdentifier = "com.sui.asyncfetch";
		result = new State<String>("Press a button to fetch data", "result");
	}

	/**
		Fetch a URL and return its content as a string.
		This runs in Haxe/C++ via the bridge — called from SwiftUI in a Task.
	**/
	@:bridge
	public static function fetchUrl(url:String):String {
		var http = new haxe.Http(url);
		var data = "";
		http.onData = function(d:String) {
			data = d;
		};
		http.onError = function(e:String) {
			data = "Error: " + e;
		};
		http.request(false);
		// Return first 500 chars to keep UI clean
		return data.length > 500 ? data.substr(0, 500) + "..." : data;
	}

	override function body():View {
		return new NavigationStack(new VStack(null, 16, [
			new Text("Async Haxe Bridge").font(FontStyle.LargeTitle),
			new ScrollView([Text.bind(result.value).font(FontStyle.Body).padding()]),
			new HStack(null, 12, [
				new Button("Fetch example.com", null, StateAction.BridgeCallLoading("result", "Loading...", "fetchUrl", "https://example.com")),
				new Button("Fetch example.com", null, StateAction.BridgeCallLoading("result", "Loading...", "fetchUrl", "https://example.com")),
			]).padding()
		]).navigationTitle("Async Fetch"));
	}
}
