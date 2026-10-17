package backend.vm;

/**
	Read an ordinary function value before evaluating its arguments.
	Neko otherwise evaluates arguments first, which can replace a mutable callback
	or move a factory's effects. A block-local value preserves Haxe order without
	adding a function boundary or changing return, exception, or receiver behavior.
 */
function render(program:NekoTypedProgramProjection, callee:String, arguments:Array<String>):String {
	final value = program.runtimeHelperName("__hxhx_call_value");
	return "({ var " + value + " = " + callee + "; " + value + "(" + arguments.join(", ") + "); })";
}
