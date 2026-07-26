/**
	Exercises one trailing optional primitive parameter through the sealed call
	contract. Haxe exposes each parameter as `Null<T>` at the callable boundary.
**/
class OptionalCalls {
	public static function optionalInt(?value:Int):Int {
		Sys.println("optional-int-callee");
		return value == null ? -1 : value;
	}

	public static function optionalBool(?value:Bool):Bool {
		Sys.println("optional-bool-callee");
		return value == null ? false : value;
	}
}
