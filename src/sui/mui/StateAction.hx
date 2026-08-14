package sui.mui;

/**
	`sui`'s conformance for `mui.state.StateAction`.

	Moved here from the `#if (mui_backend == "sui")` branch it used to live in.
	`mui` resolves it by name through `mui.Contract`, and lists it as optional
	because the six backends genuinely disagree about which of these exist.
**/
typedef StateAction = sui.state.StateAction;
