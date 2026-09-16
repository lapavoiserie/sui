package sui.mui;

/**
	`sui`'s conformance for `mui.ui.Image`: the canonical picture.

	```haxe
	new Image("asset:farceur/logo.png", "Farceur")
	new Image("https://example.org/cover.jpg", "Album cover", {width: 120, fit: Cover})
	```

	`src` names where the picture lives, by scheme (`nui.ImageSource`); `alt`
	says what it shows, and is what the renderer draws while the picture is not
	there — loading, refused, undecodable. `""` declares it decorative.

	Built on `sui.ui.Image`, so the renderer's `Image` case draws it and the
	coverage check knows it; `src` is what tells the renderer this is the
	canonical kind rather than an asset-catalog name or an SF Symbol.
**/
class Image extends sui.ui.Image {
	public function new(src:String, alt:String, ?options:mui.ui.ImageOptions) {
		super("");
		properties.set("src", src);
		properties.set("alt", alt == null ? "" : alt);
		if (options != null) {
			if (options.width != null) properties.set("width", options.width);
			if (options.height != null) properties.set("height", options.height);
			if (options.fit != null) properties.set("fit", (options.fit : String));
		}
	}
}
