package sui.mui;

import mui.ui.TextScale;

/**
	`sui`'s conformance for `mui.ui.Text`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class Text extends sui.ui.Text {
    public function new(content:String, ?scale:TextScale) {
        super(content);
        if (scale != null) font(switch (scale) {
            case Title: sui.View.FontStyle.Title;
            // Apple has no "subtitle". Headline is its semibold heading step,
            // which is what a section heading is here.
            case Subtitle: sui.View.FontStyle.Headline;
            case Body: sui.View.FontStyle.Body;
            case Caption: sui.View.FontStyle.Caption;
        });
    }
}
