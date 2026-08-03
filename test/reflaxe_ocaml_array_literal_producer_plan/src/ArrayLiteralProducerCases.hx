package;

typedef IntArrayAlias = Array<Int>;

/**
	Typed source forms used to check direct represented-array literal boundaries.

	The macro fixture reads these functions after Haxe has typed them. They are
	not runtime tests: their purpose is to prove which literal shapes the active
	planner accepts and which later shapes can form a detached construction record
	without becoming generated OCaml.
**/
class ArrayLiteralProducerCases {
	public static function ordered(first:Int, second:Int):Array<Int> {
		return [first, second];
	}

	public static function empty():Array<Int> {
		return [];
	}

	public static function bools(first:Bool, second:Bool):Array<Bool> {
		return [first, second];
	}

	public static function strings(first:String, second:String):Array<String> {
		return [first, second];
	}

	public static function emptyStrings():Array<String> {
		return [];
	}

	public static function effectfulStrings(first:String, second:String):Array<String> {
		return [stringElement(first), stringElement(second)];
	}

	public static function nested(first:Int, second:Int):Array<Array<Int>> {
		return [[first], [second]];
	}

	public static function alias(first:Int, second:Int):IntArrayAlias {
		return [first, second];
	}

	static function stringElement(value:String):String {
		return value;
	}
}
