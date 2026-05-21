import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class SettingsApp extends App {
    static function main() {}

    var username:State<String>;
    var brightness:State<Float>;
    var darkMode:State<Bool>;

    public function new() {
        super();
        appName = "Settings";
        bundleIdentifier = "com.sui.settings";
        username = new State<String>("", "username");
        brightness = new State<Float>(0.5, "brightness");
        darkMode = new State<Bool>(false, "darkMode");
    }

    override function body():View {
        return new NavigationStack(
            new ScrollView([
                new VStack(null, 20, [
                    // Text input
                    new TextField("Enter your name", "username")
                        .textFieldStyle(TextFieldStyleValue.RoundedBorder)
                        .padding(),

                    // Display the entered name
                    Text.bind('Hello, ${username.value}!')
                        .font(FontStyle.Title),

                    // Toggle
                    new Toggle("Dark Mode", "darkMode"),

                    // Slider
                    new Slider("brightness", 0, 1),
                    Text.bind('Brightness: ${brightness.value}')
                        .font(FontStyle.Caption),

                    new Spacer()
                ])
                .padding()
            ]).navigationTitle("Settings")
        );
    }
}
