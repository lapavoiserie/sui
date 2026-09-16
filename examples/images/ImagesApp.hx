import mui.App;
import mui.View;
import mui.ui.HStack;
import mui.ui.Icon;
import mui.ui.IconName;
import mui.ui.Image;
import mui.ui.Text;
import mui.ui.VStack;

/**
	Every icon of `nui.Icons`, and a picture from each source sui draws itself,
	with the failures that must show their `alt`.

	Pictures: `data:` contained and covered, `file:` (written at start-up from
	the same bytes), and three that cannot be drawn — an asset this build does
	not ship, an `http:` source, and a `data:` source that is not a PNG.
**/
class ImagesApp extends App {
	final filePath:String;

	public function new() {
		super();
		appTitle = "sui images";
		filePath = haxe.io.Path.join([Sys.getEnv("TMPDIR") != null ? Sys.getEnv("TMPDIR") : "/tmp", "sui-images-test.png"]);
		sys.io.File.saveBytes(filePath, haxe.crypto.Base64.decode(TestPicture.BASE64));
	}

	override function body():View {
		var data = "data:image/png;base64," + TestPicture.BASE64;
		var rows:Array<View> = [
			new Text("Text"),
			new HStack([
				new Text("plain"),
				new Text("Georgia", Body, {family: mui.ui.FontFamily.fromString("Georgia")}),
				new Text("bold", Body, {weight: 700}),
				new Text("italic", Body, {italic: true}),
				new Text("00:11:22", Body, {numbers: Tabular}),
			], 14),
			new Text("Icons")
		];
		var names = nui.Icons.NAMES;
		var perRow = 6;
		var i = 0;
		while (i < names.length) {
			var cells:Array<View> = [];
			for (name in names.slice(i, i + perRow))
				cells.push(new VStack([new Icon(IconName.fromString(name)), new Text(name)], 2));
			rows.push(new HStack(cells, 14));
			i += perRow;
		}
		rows.push(new Text("Pictures"));
		rows.push(new HStack([
			new Image(data, "contained", {width: 96}),
			new Image(data, "covered", {width: 64, height: 64, fit: Cover}),
			new Image("file://" + filePath, "from a file", {width: 96}),
			new Image(mui.Assets.src("test.png"), "from an asset", {width: 96}),
		], 12));
		rows.push(new HStack([
			new Image("asset:not-shipped.png", "missing asset", {width: 96, height: 48}),
			new Image("http://example.org/a.png", "http is refused", {width: 96, height: 48}),
			new Image("data:image/png;base64,SGVsbG8=", "not a PNG", {width: 96, height: 48}),
		], 12));
		return new VStack(rows, 8);
	}

	static function main() {}
}
