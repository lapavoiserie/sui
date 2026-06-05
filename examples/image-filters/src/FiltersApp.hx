import sui.App;
import sui.View;
import sui.ui.*;

/**
    Demonstrates image effect modifiers: brightness, contrast,
    saturation, grayscale. Uses sliders to control each effect
    applied to a sample view.
**/
class FiltersApp extends App {
    static function main() {}

    @:state var brightnessVal:Float = 0.0;
    @:state var contrastVal:Float = 1.0;
    @:state var saturationVal:Float = 1.0;
    @:state var grayscaleVal:Float = 0.0;

    public function new() {
        super();
        appName = "ImageFilters";
        bundleIdentifier = "com.sui.imagefilters";
    }

    override function body():View {
        return new VStack(null, 20, [
            new Text("Image Filters")
                .font(FontStyle.LargeTitle)
                .padding(),

            // Preview with all effects applied
            new GroupBox("Preview", [
                new HStack(null, 15, [
                    new Image("photo.fill")
                        .font(FontStyle.LargeTitle)
                        .foregroundColor(ColorValue.Blue),
                    new VStack([
                        new Text("Sample Content")
                            .font(FontStyle.Headline),
                        new Text("Adjust the sliders below")
                            .foregroundColor(ColorValue.Secondary)
                    ])
                ])
                .padding()
                .background(ColorValue.Blue)
                .foregroundColor(ColorValue.White)
                .cornerRadius(12)
            ])
            .brightness(brightnessVal)
            .contrast(contrastVal)
            .saturation(saturationVal)
            .grayscale(grayscaleVal)
            .padding(),

            // Controls
            new Form([
                new Section("Adjustments", [
                    new HStack([
                        new Text("Brightness"),
                        new Slider("brightnessVal", -0.5, 0.5)
                    ]),
                    new HStack([
                        new Text("Contrast"),
                        new Slider("contrastVal", 0.5, 2.0)
                    ]),
                    new HStack([
                        new Text("Saturation"),
                        new Slider("saturationVal", 0, 2.0)
                    ]),
                    new HStack([
                        new Text("Grayscale"),
                        new Slider("grayscaleVal", 0, 1.0)
                    ])
                ]),
                new Section("", [
                    new Button("Reset All", () -> {
                        brightnessVal.value = 0;
                        contrastVal.value = 1;
                        saturationVal.value = 1;
                        grayscaleVal.value = 0;
                    })
                ])
            ])
        ]);
    }
}
