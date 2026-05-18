package sui.modifiers;

import sui.View;

/**
    Represents a SwiftUI view modifier in the Haxe AST.
    Each variant maps to a SwiftUI modifier call in generated Swift code.
**/
enum ViewModifier {
    // Layout
    PaddingDefault;
    Padding(value:Float);
    PaddingEdges(edges:Edge, value:Float);
    Frame(width:Null<Float>, height:Null<Float>, alignment:Null<Alignment>);

    // Typography
    Font(style:FontStyle);
    Bold;
    Italic;
    MultilineTextAlignment(alignment:TextAlignment);

    // Colors & Appearance
    ForegroundColor(color:ColorValue);
    Background(color:ColorValue);
    Opacity(value:Float);

    // Shape
    CornerRadius(radius:Float);
    ClipShape(shape:ShapeType);

    // Navigation
    NavigationTitle(title:String);
    NavigationDestination(content:sui.View);

    // Interaction
    Disabled(isDisabled:Bool);
    LineLimit(lines:Int);

    // Styles
    TextFieldStyle(style:sui.View.TextFieldStyleValue);

    // Presentation
    Sheet(isPresentedBinding:Dynamic, content:sui.View);
    Alert(title:String, isPresentedBinding:Dynamic, message:Null<String>);
    ConfirmationDialog(title:String, isPresentedBinding:Dynamic, content:sui.View);

    // Search & Toolbar
    Searchable(textBinding:String, prompt:Null<String>);
    Toolbar(content:sui.View);
    ToolbarItem(placement:String, content:sui.View);
    Overlay(content:sui.View);

    // Animation
    Animation(curve:String, value:Dynamic);
    Transition(style:String);

    // Lifecycle
    OnAppear(actionId:Int);
    OnDisappear(actionId:Int);
    TaskOnAppear(actionId:Int);
    OnAppearAction(action:sui.state.StateAction);
    TaskAction(action:sui.state.StateAction);

    // Gestures
    OnTapGesture(action:sui.state.StateAction);

    // Appearance
    Tint(color:ColorValue);
    Badge(value:Dynamic);
    Tag(value:String);

    // Visual Effects (accept Float for static or String for state-bound)
    Blur(radius:Dynamic);
    ScaleEffect(scale:Dynamic);
    RotationEffect(degrees:Dynamic);
    Offset(x:Dynamic, y:Dynamic);

    // Image effects (accept Float for static or String for state-bound)
    Brightness(amount:Dynamic);
    Contrast(amount:Dynamic);
    Saturation(amount:Dynamic);
    Grayscale(amount:Dynamic);

    // Presentation
    FullScreenCover(isPresentedBinding:Dynamic, content:sui.View);
    Popover(isPresentedBinding:Dynamic, content:sui.View);
    ContextMenu(content:sui.View);

    // List
    SwipeActions(content:sui.View);
    Refreshable(actionId:Int);
    ListStyle(style:String);

    // Layout
    AspectRatio(ratio:Null<Float>, contentMode:String);

    // Accessibility
    AccessibilityLabel(label:String);
    /** SwiftUI `.help("…")` — tooltip text shown on hover on macOS,
        accessibility hint on iOS. **/
    Help(text:String);

    // Interaction
    OnSubmit(actionId:Int);
    OnLongPressGesture(action:sui.state.StateAction);

    // Spacing
    FixedSize(horizontal:Bool, vertical:Bool);
}

enum Edge {
    Top;
    Bottom;
    Leading;
    Trailing;
    Horizontal;
    Vertical;
    All;
}

enum ShapeType {
    Rectangle;
    RoundedRectangle(cornerRadius:Float);
    Circle;
    Capsule;
}
