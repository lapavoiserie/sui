package sui.mui;

import mui.ui.TextScale;
import mui.ui.TextStyle;

/**
	`sui`'s conformance for `mui.ui.Text`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
class Text extends sui.ui.Text {
    public function new(content:String, ?scale:TextScale, ?style:TextStyle) {
        super(content);
        // Both, and on purpose: the modifier is what the transpiled path reads
        // off the typed AST, the props are what crosses a wire and what the
        // dynamic renderer switches on.
        styled(scale == null ? null : Std.string(scale).toLowerCase(),
            style == null || style.family == null ? null : (style.family : String),
            style == null ? null : style.weight,
            style == null ? null : style.italic,
            style != null && style.numbers == mui.ui.Numbers.Tabular);
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
