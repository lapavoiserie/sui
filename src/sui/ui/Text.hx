package sui.ui;

import sui.View;

/**
    A view that displays one or more lines of read-only text.
    Maps to SwiftUI's `Text` view.

    For state interpolation, use `Text.withState()` which generates
    Swift string interpolation referencing @State vars.
**/
class Text extends View {
    public var content:String;

    /** If set, this is a Swift expression used instead of a literal string. **/
    public var swiftExpression:Null<String>;

    public function new(text:String) {
        super();
        this.content = text;
        this.viewType = "Text";
    }

    /**
        Typed-expression text. The argument can be any String-typed
        Haxe expression — state field access, array subscript, string
        interpolation, concatenation. Sui's macro inspects the typed
        AST at compile time and emits the matching Swift expression
        directly (no `{name}` template string, no text rewriter).

        ```haxe
        Text.bind(editorStartHour.value)            // → Text("\(appState.editorStartHour)")
        Text.bind('${currentPage.value} / 12')      // → Text("\(appState.currentPage) / 12")
        Text.bind(calendarNames.value[i])           // inside ForEach.byIndex(...) → Text("\(appState.calendarNames[i])")
        ```

        Falls back to a plain `Text(template)` at runtime so the
        method is callable outside the macro path (tests, views never
        reached by SwiftGenerator).
    **/
    public static function bind(template:String):Text {
        return new Text(template);
    }

    /**
        Create a text view that interpolates a state variable.
        `template` uses `{stateName}` placeholders, e.g. "Count: {count}"

        Legacy form — prefer `Text.bind(...)` which takes a typed Haxe
        expression instead of a stringly template. Kept only for
        backward compatibility; this path still depends on sui's
        deprecated `rewriteStateRefsToAppState` text pass.
    **/
    @:deprecated("Use Text.bind(stateField.value) or Text.bind('${stateField.value}') — fully typed, no text rewriter, no template strings.")
    public static function withState(template:String):Text {
        var t = new Text("");
        // Convert {name} to Swift's \(name) interpolation
        var swiftExpr = new StringBuf();
        swiftExpr.add('"');
        var i = 0;
        while (i < template.length) {
            var ch = template.charAt(i);
            if (ch == "{") {
                var end = template.indexOf("}", i);
                if (end != -1) {
                    var varName = template.substr(i + 1, end - i - 1);
                    swiftExpr.add("\\(");
                    swiftExpr.add(varName);
                    swiftExpr.add(")");
                    i = end + 1;
                    continue;
                }
            }
            if (ch == '"') swiftExpr.add('\\');
            swiftExpr.add(ch);
            i++;
        }
        swiftExpr.add('"');
        t.swiftExpression = swiftExpr.toString();
        t.content = template;
        return t;
    }
}
