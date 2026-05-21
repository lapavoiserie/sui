# Todo App

A more complex app with Observable data models, ForEach iteration, text input, and array mutations.

## Full Source

```haxe
import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.State;
import sui.state.StateAction;
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

    @:state var todos:Array<TodoItem> = [];
    @:state var newItemText:String = "";

    public function new() {
        super();
        appName = "TodoList";
        bundleIdentifier = "com.sui.todoapp";
    }

    override function body():View {
        return new NavigationStack(
            new VStack([
                new HStack(null, 8, [
                    new TextField("New item...", "newItemText")
                        .textFieldStyle(TextFieldStyleValue.RoundedBorder),
                    new Button("Add", null,
                        StateAction.CustomSwift(
                            'if !newItemText.isEmpty { todos.append(TodoItem(title: newItemText, completed: false)); newItemText = "" }'))
                ]).padding(),
                new List([
                    ForEach.byIndex(todos, i ->
                        new HStack([
                            Text.bind(todos.value[i].title)
                                .font(FontStyle.Body),
                            new Spacer(),
                            new Button("Done", null,
                                StateAction.CustomSwift("todos[i].completed.toggle()"))
                        ])
                    )
                ])
            ]).navigationTitle("Todo List")
        );
    }
}
```

## Walkthrough

### Observable Data Model

```haxe
class TodoItem extends Observable {
    public var title:String;
    public var completed:Bool;
    // ...
}
```

`TodoItem` extends `Observable`, so it generates a Swift struct that SwiftUI can observe. Properties become struct fields.

### State Arrays

```haxe
@:state var todos:Array<TodoItem> = [];
```

`@:state` can hold arrays of Observable objects. SwiftUI renders the list and updates when items are added, removed, or modified.

### Text Input + Add Button

```haxe
new TextField("New item...", "newItemText")
    .textFieldStyle(TextFieldStyleValue.RoundedBorder),
new Button("Add", null,
    StateAction.CustomSwift(
        'if !newItemText.isEmpty { todos.append(TodoItem(title: newItemText, completed: false)); newItemText = "" }'))
```

The TextField binds to `newItemText` state. The button uses `CustomSwift` to append a new `TodoItem` and clear the text field &mdash; all in generated Swift for immediate responsiveness.

### ForEach Iteration

```haxe
ForEach.byIndex(todos, i ->
    new HStack([
        Text.bind(todos.value[i].title),
        // ...
    ])
)
```

`ForEach.byIndex` iterates the `todos` array by index. The lambda receives `i:Int`, so `todos.value[i].title` typechecks in Haxe and the macro rewrites it to `appState.todos[i].title` in the emitted Swift.

### Inline State Mutation

```haxe
StateAction.CustomSwift("todos[i].completed.toggle()")
```

`CustomSwift` lets you write any Swift expression. Here it toggles a todo item's `completed` property directly.

## Run It

```bash
cd examples/todo-app
haxelib run sui run macos
```
