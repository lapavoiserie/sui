import sui.App;
import sui.View;
import sui.ui.*;
import sui.state.StateAction;

/**
    Demonstrates visual effect modifiers bound to state:
    blur, scaleEffect, rotationEffect, offset, and accessibilityLabel.

    Pass a state variable name (string) to a modifier to bind it dynamically.
    Pass a number for a static value.
**/
class EffectsApp extends App {
    static function main() {}

    @:state var rotation:Float = 0.0;
    @:state var scale:Float = 1.0;
    @:state var blurAmount:Float = 0.0;
    @:state var message:String = "Hello!";

    public function new() {
        super();
        appName = "VisualEffects";
        bundleIdentifier = "com.sui.effects";
    }

    override function body():View {
        return new VStack(null, 30, [
            new Text("Visual Effects")
                .font(FontStyle.LargeTitle)
                .padding(),

            // Text with state-bound visual effects
            Text.bind(message.value)
                .font(FontStyle.Title)
                .foregroundColor(ColorValue.Blue)
                .scaleEffect(scale)
                .rotationEffect(rotation)
                .blur(blurAmount)
                .padding(),

            // Controls
            new VStack(null, 10, [
                new HStack(null, 10, [
                    new Text("Blur"),
                    new Slider("blurAmount", 0, 10)
                ]).padding(),

                new HStack(null, 20, [
                    new Button("Spin", null, StateAction.Increment("rotation", 45)),
                    new Button("Grow", null, StateAction.CustomSwift("scale += 0.2")),
                    new Button("Shrink", null, StateAction.CustomSwift("scale = max(0.2, scale - 0.2)")),
                    new Button("Reset", null, StateAction.CustomSwift("rotation = 0; scale = 1.0; blurAmount = 0"))
                ])
            ]),

            // Card with static effects
            new GroupBox("Preview", [
                new Text("Static effects: rotated 10 degrees")
                    .padding()
                    .background(ColorValue.Blue)
                    .foregroundColor(ColorValue.White)
                    .cornerRadius(8)
                    .rotationEffect(10.0)
                    .accessibilityLabel("Interactive preview card")
            ])
        ]);
    }
}
