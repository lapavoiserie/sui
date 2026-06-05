import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

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
                    new Button("Apple", () -> selectedItem.value = "Apple"),
                    new Button("Banana", () -> selectedItem.value = "Banana"),
                    new Button("Cherry", () -> selectedItem.value = "Cherry")
                ]),
                new Section("Veggies", [
                    new Button("Carrot", () -> selectedItem.value = "Carrot"),
                    new Button("Broccoli", () -> selectedItem.value = "Broccoli")
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
