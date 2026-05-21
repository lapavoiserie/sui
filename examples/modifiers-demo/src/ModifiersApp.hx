import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class ModifiersApp extends App {
    static function main() {}

    var username:State<String>;
    var notifications:State<Bool>;
    var volume:State<Float>;
    var showSheet:State<Bool>;
    var showAlert:State<Bool>;
    var searchText:State<String>;

    public function new() {
        super();
        appName = "Modifiers";
        bundleIdentifier = "com.sui.modifiers";
        username = new State<String>("", "username");
        notifications = new State<Bool>(true, "notifications");
        volume = new State<Float>(0.5, "volume");
        showSheet = new State<Bool>(false, "showSheet");
        showAlert = new State<Bool>(false, "showAlert");
        searchText = new State<String>("", "searchText");
    }

    override function body():View {
        return new NavigationStack(
            new Form([
                new Section("Profile", [
                    new TextField("Username", "username")
                        .textFieldStyle(TextFieldStyleValue.RoundedBorder),
                    Text.bind('Hello, ${username.value}!')
                        .font(FontStyle.Headline)
                ]),
                new Section("Preferences", [
                    new Toggle("Notifications", "notifications"),
                    new Slider("volume", 0, 1),
                    Text.bind('Volume: ${volume.value}')
                        .font(FontStyle.Caption)
                ]),
                new Section("Actions", [
                    new Button("Show Sheet", null, StateAction.SetValue("showSheet", true)),
                    new Button("Show Alert", null, StateAction.SetValue("showAlert", true))
                ])
            ])
            .navigationTitle("Settings")
            .searchable("searchText", "Search settings...")
            .sheet("showSheet",
                new VStack(null, 20, [
                    new Text("This is a sheet!")
                        .font(FontStyle.Title),
                    new Text("Swipe down to dismiss")
                        .foregroundColor(ColorValue.Secondary)
                ])
                .padding()
            )
            .alert("Hello!", "showAlert", "This alert was triggered from Haxe.")
        );
    }
}
