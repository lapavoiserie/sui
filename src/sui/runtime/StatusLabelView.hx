package sui.runtime;

/**
    What a menu bar extra shows before it is opened: the label of a
    `@:surface(Status)` declaration, as a node the renderer reads.

    Mounted as a root of its own, under the surface's id plus `ROOT_SUFFIX`,
    beside the panel's root. A root because a label is read like a view: the
    badge comes from @:state, the read is recorded while the root is built,
    and a write rebuilds it -- which is the only way a value can reach a
    `MenuBarExtra` label, drawn by AppKit in a status item.

    Not a declared control (`sui.ui`): nothing writes one in markup. It exists
    only where `sui.mui.App` mounts it.
**/
class StatusLabelView extends sui.View {
    /** Appended to the Status surface's id to name its label's root. **/
    public static inline var ROOT_SUFFIX = "#label";

    public var title:String;
    public var icon:String;
    /** The badge. Not `badge`: `sui.View` has one, a modifier. Crosses as the `badge` property. **/
    public var count:Int;

    public function new(title:String, ?icon:String, ?badge:Int) {
        super();
        this.viewType = "StatusLabel";
        this.title = title == null ? "" : title;
        this.icon = icon == null ? "" : icon;
        this.count = badge == null ? 0 : badge;
        properties.set("title", this.title);
        properties.set("icon", this.icon);
        properties.set("badge", Std.string(this.count));
    }
}
