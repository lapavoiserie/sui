package sui.mui;


/**
	`sui`'s conformance for `mui.ViewComponent`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
typedef ViewComponent = sui.ViewComponent;
