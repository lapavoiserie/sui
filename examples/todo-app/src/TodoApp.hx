import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.Observable;

class TodoItem extends Observable {
    public var title:String;
    public var completed:Bool;

    public function new(title:String = "", completed:Bool = false) {
        super();
        this.title = title;
        this.completed = completed;
    }
}

class TodoApp extends App {
    static function main() {}

    var todos:State<Array<TodoItem>>;
    var newItemText:State<String>;

    public function new() {
        super();
        appName = "TodoList";
        bundleIdentifier = "com.sui.todoapp";
        todos = new State<Array<TodoItem>>([], "todos");
        newItemText = new State<String>("", "newItemText");
    }

    override function body():View {
        return new NavigationStack(
            new VStack([
                new HStack(null, 8, [
                    new TextField("New item...", "newItemText")
                        .textFieldStyle(TextFieldStyleValue.RoundedBorder),
                    new Button("Add", () -> {
                        // newItemText is fresh here: the TextField's
                        // Swift binding writes back to the Haxe mirror.
                        if (newItemText.value != "") {
                            todos.value = todos.value.concat([new TodoItem(newItemText.value, false)]);
                            newItemText.value = "";
                        }
                    })
                ]).padding(),
                new List([
                    ForEach.byIndex(todos, i ->
                        new HStack([
                            Text.bind(todos.value[i].title)
                                .font(FontStyle.Body),
                            new Spacer(),
                            new Button("Done", () -> {
                                todos.value[i].completed = !todos.value[i].completed;
                                todos.value = todos.value; // re-assign to notify SwiftUI
                            })
                        ])
                    )
                ])
            ]).navigationTitle("Todo List")
        );
    }
}
