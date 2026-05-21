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
                    new Button("Done", null,
                        StateAction.CustomSwift("todos[i].completed.toggle()"))
                ])
            )
        ]);
    }
}
```

Mutating `todos[i].completed` directly in Swift triggers a re-render because the array is `@State`. No manual notification needed.

## Key Points

- Extend `Observable` for any data model used in `@:state` arrays
- Public properties become Swift struct fields automatically
- Reactivity comes from `@State` on the array &mdash; no manual change tracking required
- Use `Text.bind(array.value[index].property)` to display properties (inside `ForEach.byIndex`, where `index` is the lambda parameter)
- Mutate with `StateAction.CustomSwift()` for direct Swift property access
