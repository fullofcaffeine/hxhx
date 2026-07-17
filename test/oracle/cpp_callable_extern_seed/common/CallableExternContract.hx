/**
	Exercises the erased Haxe function constraint beside a concrete callable.

	The constraint may forget the argument list, but it must not turn a function
	value into a generated class. The concrete callback keeps its full signature.
**/
class CallableExternContract {
	public static function describe(value:haxe.Constraints.Function):String {
		return value == null ? "null" : "callable";
	}

	public static function apply(value:Int->Int, input:Int):Int {
		return value(input);
	}

	public static function lines():Array<String> {
		final addThree = (value:Int) -> value + 3;
		return [
			"constraint=" + describe(addThree),
			"null=" + describe(null),
			"apply=" + apply(addThree, 4)
		];
	}
}
