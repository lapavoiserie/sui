package sui.nui;

/**
	The describers, as a map the build writes.

	Empty in the source and filled by `sui.nui.Derive` from what the controls
	declare. Keyed by the exact class path, so a caller walks up the superclass
	chain and the nearest declared ancestor wins.
**/
@:build(sui.nui.Derive.build())
class Derived {}
