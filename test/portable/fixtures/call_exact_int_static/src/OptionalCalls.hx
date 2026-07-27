/**
	Exercises one trailing optional primitive or exact String parameter through
	the sealed call contract. Haxe exposes optional value-type parameters as
	`Null<T>`; optional String keeps the exact Haxe String carrier, including its
	dedicated null sentinel.
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

	public static function optionalString(?value:String):String {
		Sys.println("optional-string-callee");
		return value == null ? "missing" : value;
	}
}
