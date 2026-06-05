# Observable

`Observable` is a base class for data models. Extend it to define structured data types that can be stored in `@State` arrays and rendered with `ForEach`.

The framework generates a Swift struct (`Identifiable`, `Hashable`) from your class. Reactivity is handled automatically through the `@State` array that holds the objects &mdash; you don't need to manually notify about changes.

## Defining an Observable

```haxe
class TodoItem extends Observable {
    public var title:String;
    public var completed:Bool;

    public function new(title:String = "", completed:Bool = false) {
        super();
        this.title = title;
        this.completed = completed;
    }
}
```

This generates:

```swift
struct TodoItem: Identifiable, Hashable {
    let id = UUID()
    var title: String = ""
    var completed: Bool = false
}
```

## Using with State

Observable objects are stored in `@:state` arrays. SwiftUI re-renders automatically when the array or its elements change:

```haxe
class TodoApp extends App {
    @:state var todos:Array<TodoItem> = [];

    public function new() {
        super();
    }

    override function body():View {
        return new List([
            ForEach.byIndex(todos, i ->
                new HStack([
                    Text.bind(todos.value[i].title),
                    new Spacer(),
                    new Button("Done", () -> {
                        todos.value[i].completed = !todos.value[i].completed;
                        todos.value = todos.value; // re-assign to notify SwiftUI
                    })
                ])
            )
        ]);
    }
}
```

The row closure references the iteration index `i`; the macro lifts it into an indexed
builder so Swift dispatches it with the live loop index. Re-assigning `todos.value`
notifies SwiftUI to re-render.

## Key Points

- Extend `Observable` for any data model used in `@:state` arrays
- Public properties become Swift struct fields automatically
- Reactivity comes from `@State` on the array &mdash; no manual change tracking required
- Use `Text.bind(array.value[index].property)` to display properties (inside `ForEach.byIndex`, where `index` is the lambda parameter)
- Mutate from an action closure (`item.prop = ...; array.value = array.value;`) to re-render
