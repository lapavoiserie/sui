import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;

class SplitApp extends App {
    static function main() {}

    var selectedItem:State<String>;

    public function new() {
        super();
        appName = "SplitView";
        bundleIdentifier = "com.sui.ipadsplit";
        selectedItem = new State<String>("Welcome", "selectedItem");
    }

    override function body():View {
        return new NavigationSplitView(
            // Sidebar
            new List([
                new Section("Fruits", [
                    new Button("Apple", null, StateAction.SetValue("selectedItem", "Apple")),
                    new Button("Banana", null, StateAction.SetValue("selectedItem", "Banana")),
                    new Button("Cherry", null, StateAction.SetValue("selectedItem", "Cherry"))
                ]),
                new Section("Veggies", [
                    new Button("Carrot", null, StateAction.SetValue("selectedItem", "Carrot")),
                    new Button("Broccoli", null, StateAction.SetValue("selectedItem", "Broccoli"))
                ])
            ]).navigationTitle("Items"),
            // Detail
            new VStack(null, 20, [
                Text.bind('Selected: ${selectedItem.value}')
                    .font(FontStyle.LargeTitle),
                new Text("Tap an item in the sidebar")
                    .foregroundColor(ColorValue.Secondary)
            ])
        );
    }
}
