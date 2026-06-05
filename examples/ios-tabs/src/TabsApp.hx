import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;

class TabsApp extends App {
    static function main() {}

    var taskCount:State<Int>;
    var notesText:State<String>;

    public function new() {
        super();
        appName = "MyTabs";
        bundleIdentifier = "com.sui.iostabs";
        taskCount = new State<Int>(0, "taskCount");
        notesText = new State<String>("", "notesText");
    }

    override function body():View {
        return new TabView([
            {
                label: "Home",
                systemImage: "house.fill",
                content: new NavigationStack(
                    new VStack(null, 20, [
                        Image.systemImage("swift")
                            .font(FontStyle.LargeTitle)
                            .foregroundColor(ColorValue.Orange),
                        new Text("Welcome to Haxe on iOS!")
                            .font(FontStyle.Title),
                        new Text("Built with sui")
                            .foregroundColor(ColorValue.Secondary)
                    ]).navigationTitle("Home")
                )
            },
            {
                label: "Counter",
                systemImage: "number.circle",
                content: new NavigationStack(
                    new VStack(null, 20, [
                        Text.bind('Tasks: ${taskCount.value}')
                            .font(FontStyle.LargeTitle),
                        new HStack(null, 16, [
                            new Button("-", () -> taskCount.value--),
                            new Button("+", () -> taskCount.value++)
                        ])
                    ]).navigationTitle("Counter")
                )
            },
            {
                label: "Notes",
                systemImage: "note.text",
                content: new NavigationStack(
                    new VStack(null, 16, [
                        new TextField("Write something...", "notesText")
                            .textFieldStyle(TextFieldStyleValue.RoundedBorder)
                            .padding(),
                        Text.bind(notesText.value)
                            .font(FontStyle.Body)
                            .padding()
                    ]).navigationTitle("Notes")
                )
            }
        ]);
    }
}
