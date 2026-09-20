package sui.ui;

import sui.View;

/**
    A view that displays an image.
    Maps to SwiftUI's `Image`.
**/
@:node("Image")
class Image extends View {
    /**
        The canon's source, with a scheme -- `asset:`, `file:`, `https:`.

        `DynamicView.swift` has preferred it over `name` for as long as trees
        have arrived over the wire; the Haxe class had only the asset-catalog
        name, so markup could name an asset and nothing else.
    **/
    @:prop public var src:Null<String>;

    /** What the image says, for VoiceOver. **/
    @:prop public var alt:Null<String>;

    public var name:String;
    public var systemName:Null<String>;

    /** Create an image from an asset catalog name. **/
    public function new(name:String, ?alt:String) {
        super();
        this.viewType = "Image";
        this.name = name;
        // A bare asset name IS a source; the scheme is what the canon adds,
        // and a name written without one still has to reach the renderer.
        this.src = name;
        this.alt = alt;
    }

    /** Create an image from an SF Symbol name. **/
    @:swiftName("Image")
    public static function systemImage(@:swiftLabel("systemName") systemName:String):Image {
        var img = new Image("");
        img.systemName = systemName;
        return img;
    }

    public function resizable():Image {
        modifierChain.push(sui.modifiers.ViewModifier.FixedSize(false, false));
        properties.set("resizable", true);
        return this;
    }
}
