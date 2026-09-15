package sui.ui;

import nui.Node;

/**
	A node drawn by a component the application links, not by a case of the
	renderer.

	`DynamicView.swift` switches on a fixed list of types, and that list is what
	`sui.macros.DynamicCoverage` checks a `body()` against. A native component —
	a level meter from `vui`, say — is not in it and should not have to be: its
	SwiftUI view ships with the library that implements it, and is found at
	runtime by its type (see `SuiComponent` in `DynamicView.swift`).

	So this node is not judged by the coverage check. That is not a hole in the
	check: whoever builds one has already decided, at compile time, that an
	implementation is linked — `vui.Vui.view` refuses to compile otherwise. A
	type that nobody registered after all draws what an unknown type draws.

	The node it was made from is kept whole, so describing the tree for another
	surface (`sui.nui.Describe`) sends it unchanged, typed props included.
**/
class NativeComponent extends sui.View {
	/** What this node stands for, as it was given. **/
	public final node:Node;

	public function new(node:Node) {
		super();
		this.node = node;
		viewType = node.type;
		for (key in node.props.keys())
			switch (node.props.get(key)) {
				case PString(v): properties.set(key, v);
				case PInt(v): properties.set(key, v);
				case PFloat(v): properties.set(key, v);
				case PBool(v): properties.set(key, v);
				case _:
			}
	}
}
