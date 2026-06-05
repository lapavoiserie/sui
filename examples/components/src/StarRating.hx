import sui.ViewComponent;
import sui.View;
import sui.ui.*;

/**
    A reusable star rating component.
    Generates a separate SwiftUI struct with @Binding for the rating.
**/
class StarRating extends ViewComponent {
    public var label:String;
    @:swiftBinding public var rating:Int;

    public function new(@:swiftLabel("label") label:String, @:swiftLabel("rating") @:swiftBinding rating:String) {
        super();
        this.label = label;
    }

    override function body():View {
        return new HStack([
            new Text(label)
                .font(FontStyle.Headline),
            new Spacer(),
            Text.bind('${rating} / 5')
                .foregroundColor(ColorValue.Orange)
        ]);
    }
}
