package sui.mui;

/**
	`sui`'s conformance for `mui.ui.PickerBinding`: the name of the cell holding
	the chosen option's index, `-1` for none.
**/
abstract PickerBinding(String) {
	public inline function new(v:String) this = v;

	@:from static inline function fromState(s:sui.state.State<Int>):PickerBinding
		return new PickerBinding(s.name);

	public inline function unwrap():String return this;
}
