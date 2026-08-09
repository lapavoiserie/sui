import sui.App;
import sui.View;
import sui.ui.Text;
import sui.ui.VStack;

/** The smallest app both render paths must still accept. **/
class PathFixture extends App {
    static function main() {}

    public function new() {
        super();
        appName = "PathFixture";
        bundleIdentifier = "com.sui.pathfixture";
    }

    override function body():View {
        return new VStack(null, 8, [new Text("hello")]);
    }
}
