package sui.mui;


/**
	`sui`'s conformance for `mui.ui.ToggleBinding`.

	`mui` resolves this by name through `mui.Contract` and `mui.macros.Bind`,
	which is why nothing in `mui` mentions `sui`. Moved here, unchanged, from the
	`#if (mui_backend == "sui")` branch it used to live in.
**/
abstract ToggleBinding(String) {
    public inline function new(v:String) this = v;

    @:from static inline function fromState(s:sui.state.State<Bool>):ToggleBinding
        return new ToggleBinding(s.name);

    public inline function unwrap():String return this;
}
