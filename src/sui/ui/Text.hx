package sui.ui;

import sui.View;

/**
    A view that displays one or more lines of read-only text.
    Maps to SwiftUI's `Text` view.

    For state interpolation, use `Text.withState()` which generates
    Swift string interpolation referencing @State vars.
**/
@:node("Text")
class Text extends View {
    @:prop("text") public var content:String;

    /**
        How the canon says this text is set (`nui.TextStyle`): a scale, a
        family the application ships, a weight, italic, and digits of one
        width. Fields rather than modifiers, because a prop is what crosses a
        wire intact -- see nui's node model.
    **/
    @:prop public var scale:Null<nui.Scale>;

    @:prop public var family:Null<String>;

    @:prop public var weight:Null<Int>;

    @:prop("italic") public var italicFace:Null<Bool>;

    @:prop public var numbers:Null<nui.Numbers>;

    /** If set, this is a Swift expression used instead of a literal string. **/
    public var swiftExpression:Null<String>;

    public function new(text:String) {
        super();
        this.content = text;
        this.viewType = "Text";
    }

    /** Say how it is set. What SwiftUI applies is decided where it draws. **/
    public function styled(?scale:nui.Scale, ?family:String, ?weight:Int, ?italic:Bool, ?tabular:nui.Numbers):Text {
        // `nui.Scale` normalised it on the way in, whatever said it.
        if (scale != null) this.scale = scale;
        if (family != null && family != "") this.family = family;
        if (weight != null) this.weight = nui.TextStyle.weightOf(weight);
        if (italic != null) this.italicFace = italic;
        if (tabular) this.numbers = tabular;
        return this;
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
