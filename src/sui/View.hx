package sui;

import sui.modifiers.ViewModifier;

/**
    Base type representing a SwiftUI view.
    All UI components extend this class.
    Views are compile-time only — they build an AST that macros convert to Swift.
**/
class View {
    public var viewType:String;
    public var children:Array<View>;
    public var modifierChain:Array<ViewModifier>;
    public var properties:Map<String, Dynamic>;

    public function new() {
        children = [];
        modifierChain = [];
        properties = new Map();
        viewType = Type.getClassName(Type.getClass(this));
    }

    /** Override in subclasses to define the view body. **/
    public function body():View {
        return this;
    }

    // --- Modifier methods (return self for chaining) ---

    public function padding(?value:Float):View {
        if (value != null)
            modifierChain.push(ViewModifier.Padding(value));
        else
            modifierChain.push(ViewModifier.PaddingDefault);
        return this;
    }

    public function font(style:FontStyle):View {
        modifierChain.push(ViewModifier.Font(style));
        return this;
    }

    public function foregroundColor(color:ColorValue):View {
        modifierChain.push(ViewModifier.ForegroundColor(color));
        return this;
    }

    /** Set the foreground colour from a hex string held in a state
        variable. `expr` is emitted verbatim in the generated Swift body
        and therefore picked up by the macro's state-prefix pass —
        plain names like `calendarColor` resolve to
        `appState.calendarColor`, and subscripted forms like
        `calendarColors[i]` resolve to `appState.calendarColors[i]`
        (the per-iteration case for ForEach). Invalid hex falls back to
        `.primary` via the nil-coalescing operator on `Color(suiHex:)`. **/
    /** Accepts either a string literal (legacy stringly expr) or a
        typed `State<String>` field reference — the macro extracts
        the right Swift expression in both cases, no `.value`
        ceremony at the call site. **/
    public function foregroundHex(expr:Dynamic):View {
        modifierChain.push(ViewModifier.ForegroundHex(expr));
        return this;
    }

    /** Same as `foregroundHex` but for the background fill. **/
    public function backgroundHex(expr:Dynamic):View {
        modifierChain.push(ViewModifier.BackgroundHex(expr));
        return this;
    }

    public function frame(?width:Float, ?height:Float, ?alignment:Alignment):View {
        modifierChain.push(ViewModifier.Frame(width, height, alignment));
        return this;
    }

    /** Stretch the view horizontally to fill its parent. Compiles to
        `.frame(maxWidth: .infinity)`. Useful for views that don't have
        an intrinsic preferred width (e.g. Lists inside sheets). **/
    public function fillWidth():View {
        modifierChain.push(ViewModifier.FillWidth);
        return this;
    }

    /** Stretch the view vertically to fill its parent. Compiles to
        `.frame(maxHeight: .infinity)`. The canonical use case is
        `List`-inside-`.sheet`: SwiftUI's `List` collapses to zero
        height inside a sheet's content closure because its parent's
        intrinsic height doesn't reserve room for a scrollable list. **/
    public function fillHeight():View {
        modifierChain.push(ViewModifier.FillHeight);
        return this;
    }

    /** Shorthand for `.fillWidth().fillHeight()`. **/
    public function fillBoth():View {
        modifierChain.push(ViewModifier.FillBoth);
        return this;
    }

    /** Pin this view to its **intrinsic** size on either axis. Compiles
        to `.fixedSize(horizontal:, vertical:)`. Crucial for views like
        `List` and `ScrollView` whose default size is "fill available" —
        in some layout contexts (notably `.sheet` content on macOS,
        where the container sizes to its children's intrinsic heights)
        their default behaviour resolves to zero. Pinning to intrinsic
        size makes them report the sum of their content heights
        instead. **/
    public function fixedSize(horizontal:Bool = false, vertical:Bool = true):View {
        modifierChain.push(ViewModifier.FixedSize(horizontal, vertical));
        return this;
    }

    public function background(color:ColorValue):View {
        modifierChain.push(ViewModifier.Background(color));
        return this;
    }

    public function cornerRadius(radius:Float):View {
        modifierChain.push(ViewModifier.CornerRadius(radius));
        return this;
    }

    public function opacity(value:Float):View {
        modifierChain.push(ViewModifier.Opacity(value));
        return this;
    }

    public function bold():View {
        modifierChain.push(ViewModifier.Bold);
        return this;
    }

    public function italic():View {
        modifierChain.push(ViewModifier.Italic);
        return this;
    }

    public function multilineTextAlignment(alignment:TextAlignment):View {
        modifierChain.push(ViewModifier.MultilineTextAlignment(alignment));
        return this;
    }

    public function navigationTitle(title:String):View {
        modifierChain.push(ViewModifier.NavigationTitle(title));
        return this;
    }

    public function disabled(isDisabled:Bool = true):View {
        modifierChain.push(ViewModifier.Disabled(isDisabled));
        return this;
    }

    public function lineLimit(lines:Int):View {
        modifierChain.push(ViewModifier.LineLimit(lines));
        return this;
    }

    public function textFieldStyle(style:TextFieldStyleValue):View {
        modifierChain.push(ViewModifier.TextFieldStyle(style));
        return this;
    }

    /** Apply a SwiftUI ButtonStyle. The most useful values for visual
        hierarchy are `BorderedProminent` (the "filled" CTA look) and
        `Bordered` (a thin outline). Use `Plain` to strip the default
        chrome — handy inside Lists, sidebars and tappable cells. **/
    /** Apply a SwiftUI PickerStyle. Most useful: `Segmented` for the
        native macOS switcher control. **/
    public function pickerStyle(style:PickerStyleValue):View {
        modifierChain.push(ViewModifier.PickerStyle(style));
        return this;
    }

    /** Run a `StateAction` whenever the named state changes (e.g.
        when a `Picker` writes its new selection). Maps to SwiftUI's
        `.onChange(of:_:)`. **/
    public function onChange(stateName:String, action:sui.state.StateAction):View {
        modifierChain.push(ViewModifier.OnChange(stateName, action));
        return this;
    }

    public function buttonStyle(style:ButtonStyleValue):View {
        modifierChain.push(ViewModifier.ButtonStyle(style));
        return this;
    }

    public function searchable(textBinding:String, ?prompt:String):View {
        modifierChain.push(ViewModifier.Searchable(textBinding, prompt));
        return this;
    }

    public function sheet(isPresentedBinding:Dynamic, content:View):View {
        modifierChain.push(ViewModifier.Sheet(isPresentedBinding, content));
        return this;
    }

    public function alert(title:String, isPresentedBinding:Dynamic, ?message:String):View {
        modifierChain.push(ViewModifier.Alert(title, isPresentedBinding, message));
        return this;
    }

    public function confirmationDialog(title:String, isPresentedBinding:Dynamic, content:View):View {
        modifierChain.push(ViewModifier.ConfirmationDialog(title, isPresentedBinding, content));
        return this;
    }

    public function toolbar(content:View):View {
        modifierChain.push(ViewModifier.Toolbar(content));
        return this;
    }

    /** Add a toolbar item with a specific placement. **/
    public function toolbarItem(placement:String, content:View):View {
        modifierChain.push(ViewModifier.ToolbarItem(placement, content));
        return this;
    }

    /** Animate changes. Curve: "default", "easeIn", "easeOut", "easeInOut", "spring", "linear", "bouncy". **/
    public function animation(curve:String, ?value:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Animation(curve, value));
        return this;
    }

    /** Transition for conditional view enter/exit: "slide", "opacity", "scale", "move", "push". **/
    public function transition(style:String):View {
        modifierChain.push(ViewModifier.Transition(style));
        return this;
    }

    public function overlay(content:View):View {
        modifierChain.push(ViewModifier.Overlay(content));
        return this;
    }

    /** Define a navigation destination for String-based programmatic navigation. **/
    public function navigationDestination(content:View):View {
        modifierChain.push(ViewModifier.NavigationDestination(content));
        return this;
    }

    /** Add a tap gesture with a declarative StateAction. **/
    public function onTapGesture(action:sui.state.StateAction):View {
        modifierChain.push(ViewModifier.OnTapGesture(action));
        return this;
    }

    /** Set the tint/accent color for this view and its children. **/
    public function tint(color:ColorValue):View {
        modifierChain.push(ViewModifier.Tint(color));
        return this;
    }

    /** Add a badge to a tab item or list row. **/
    public function badge(value:Dynamic):View {
        modifierChain.push(ViewModifier.Badge(value));
        return this;
    }

    /** Tag a view with a value for use in Picker selection. **/
    public function tag(value:String):View {
        modifierChain.push(ViewModifier.Tag(value));
        return this;
    }

    /** Apply a blur effect. Pass a Float or a State<Float>. **/
    public function blur(radius:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Blur(radius));
        return this;
    }

    /** Scale the view. Pass a Float or a State<Float>. **/
    public function scaleEffect(scale:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.ScaleEffect(scale));
        return this;
    }

    /** Rotate the view in degrees. Pass a Float or a State<Float>. **/
    public function rotationEffect(degrees:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.RotationEffect(degrees));
        return this;
    }

    /** Offset the view position. Pass Floats or State<Float>s. **/
    public function offset(x:sui.state.StateOr<Float>, y:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Offset(x, y));
        return this;
    }

    /** Present a full-screen modal. **/
    public function fullScreenCover(isPresentedBinding:Dynamic, content:View):View {
        modifierChain.push(ViewModifier.FullScreenCover(isPresentedBinding, content));
        return this;
    }

    /** Add a long-press context menu. **/
    public function contextMenu(content:View):View {
        modifierChain.push(ViewModifier.ContextMenu(content));
        return this;
    }

    /** Add swipe actions to a list row. **/
    public function swipeActions(content:View):View {
        modifierChain.push(ViewModifier.SwipeActions(content));
        return this;
    }

    /** Add pull-to-refresh to a list. **/
    public function refreshable(action:() -> Void):View {
        var actionId = sui.ui.Button._nextActionId++;
        sui.ui.Button._actionRegistry.set(actionId, action);
        modifierChain.push(ViewModifier.Refreshable(actionId));
        return this;
    }

    /** Set list style (inset, grouped, plain, sidebar). **/
    public function listStyle(style:String):View {
        modifierChain.push(ViewModifier.ListStyle(style));
        return this;
    }

    /** Constrain aspect ratio. **/
    public function aspectRatio(?ratio:Float, contentMode:String = "fit"):View {
        modifierChain.push(ViewModifier.AspectRatio(ratio, contentMode));
        return this;
    }

    /** Set accessibility label. **/
    public function accessibilityLabel(label:String):View {
        modifierChain.push(ViewModifier.AccessibilityLabel(label));
        return this;
    }

    /** Adjust brightness. Pass a Float or a State<Float>. **/
    public function brightness(amount:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Brightness(amount));
        return this;
    }

    /** Adjust contrast. Pass a Float or a State<Float>. **/
    public function contrast(amount:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Contrast(amount));
        return this;
    }

    /** Adjust color saturation. Pass a Float or a State<Float>. **/
    public function saturation(amount:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Saturation(amount));
        return this;
    }

    /** Apply grayscale effect. Pass a Float or a State<Float>. **/
    public function grayscale(amount:sui.state.StateOr<Float>):View {
        modifierChain.push(ViewModifier.Grayscale(amount));
        return this;
    }

    /** Present a popover. **/
    public function popover(isPresentedBinding:Dynamic, content:View):View {
        modifierChain.push(ViewModifier.Popover(isPresentedBinding, content));
        return this;
    }

    /** Run a closure on form/text field submit. **/
    public function onSubmit(action:() -> Void):View {
        var actionId = sui.ui.Button._nextActionId++;
        sui.ui.Button._actionRegistry.set(actionId, action);
        modifierChain.push(ViewModifier.OnSubmit(actionId));
        return this;
    }

    /** Long press gesture with a StateAction. **/
    public function onLongPressGesture(action:sui.state.StateAction):View {
        modifierChain.push(ViewModifier.OnLongPressGesture(action));
        return this;
    }

    /** Run a StateAction when the view appears. **/
    public function onAppearAction(action:sui.state.StateAction):View {
        modifierChain.push(ViewModifier.OnAppearAction(action));
        return this;
    }

    /** Run a StateAction as an async task when the view appears. **/
    public function taskAction(action:sui.state.StateAction):View {
        modifierChain.push(ViewModifier.TaskAction(action));
        return this;
    }

    /** Run a closure when the view appears. Runs in Haxe via the bridge. **/
    public function onAppear(action:() -> Void):View {
        var actionId = sui.ui.Button._nextActionId++;
        sui.ui.Button._actionRegistry.set(actionId, action);
        modifierChain.push(ViewModifier.OnAppear(actionId));
        return this;
    }

    /** Run a closure when the view disappears. Runs in Haxe via the bridge. **/
    public function onDisappear(action:() -> Void):View {
        var actionId = sui.ui.Button._nextActionId++;
        sui.ui.Button._actionRegistry.set(actionId, action);
        modifierChain.push(ViewModifier.OnDisappear(actionId));
        return this;
    }

    /** Run an async closure when the view appears. Runs in Haxe via the bridge. **/
    public function task(action:() -> Void):View {
        var actionId = sui.ui.Button._nextActionId++;
        sui.ui.Button._actionRegistry.set(actionId, action);
        modifierChain.push(ViewModifier.TaskOnAppear(actionId));
        return this;
    }
}

enum FontStyle {
    LargeTitle;
    Title;
    Title2;
    Title3;
    Headline;
    Subheadline;
    Body;
    Callout;
    Footnote;
    Caption;
    Caption2;
    Custom(name:String, size:Float);
}

enum ColorValue {
    Primary;
    Secondary;
    Accent;
    Red;
    Orange;
    Yellow;
    Green;
    Blue;
    Purple;
    Pink;
    White;
    Black;
    Gray;
    Clear;
    Custom(hex:String);
}

enum Alignment {
    Center;
    Leading;
    Trailing;
    Top;
    Bottom;
    TopLeading;
    TopTrailing;
    BottomLeading;
    BottomTrailing;
}

enum TextAlignment {
    Leading;
    Center;
    Trailing;
}

enum TextFieldStyleValue {
    Automatic;
    RoundedBorder;
    Plain;
}

enum ButtonStyleValue {
    Automatic;
    Plain;
    Borderless;
    Bordered;
    BorderedProminent;
    Link;
}

enum PickerStyleValue {
    Automatic;
    Inline;
    Menu;
    Palette;
    /** macOS / iOS / iPadOS — the segmented "switcher" control,
        typical for view-mode toolbars. **/
    Segmented;
    /** iOS only. **/
    Wheel;
}
