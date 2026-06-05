import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.StateAction;

/**
    Demonstrates the new input views: Stepper, DatePicker,
    ColorPicker, DisclosureGroup, GroupBox, ProgressView, Gauge, and Link.
**/
class FormApp extends App {
    static function main() {}

    @:state var quantity:Int = 1;
    @:state var brightness:Float = 0.75;
    @:state var notifications:Bool = true;
    @:state var darkMode:Bool = false;
    @:state var username:String = "";
    @:state var password:String = "";

    public function new() {
        super();
        appName = "FormDemo";
        bundleIdentifier = "com.sui.formdemo";
    }

    override function body():View {
        return new NavigationStack(
            new Form([
                new Section("Profile", [
                    new TextField("Username", "username"),
                    new SecureField("Password", "password"),
                    new Stepper("Quantity", "quantity", 1, 99),
                    Text.bind('Selected: ${quantity.value} items')
                        .foregroundColor(ColorValue.Secondary)
                ]),
                new Section("Preferences", [
                    new Toggle("Notifications", "notifications"),
                    new Toggle("Dark Mode", "darkMode"),
                    new Gauge("Brightness", "brightness", 0.0, 1.0)
                ]),
                new Section("Progress", [
                    new ProgressView("Loading data..."),
                    new ProgressView("Downloading", "brightness", 1.0)
                ]),
                new DisclosureGroup("Advanced Settings", [
                    new Toggle("Debug Mode", "darkMode"),
                    new Text("Version 1.0.0")
                        .foregroundColor(ColorValue.Secondary)
                ]),
                new GroupBox("Links", [
                    new Link("Visit Website", "https://pign.github.io/sui"),
                    new Link("GitHub", "https://github.com/Pign/sui")
                ])
            ]).navigationTitle("Form Demo")
        );
    }
}
