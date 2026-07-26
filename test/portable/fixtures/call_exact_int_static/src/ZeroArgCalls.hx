/**
	Provides zero-argument methods for every result representation currently
	admitted by the sealed direct-static call matrix.
**/
class ZeroArgCalls {
	public static function exactCount():Int {
		Sys.println("zero-int-callee");
		return 17;
	}

	public static function exactFlag():Bool {
		Sys.println("zero-bool-callee");
		return false;
	}

	public static function nullableCount():Null<Int> {
		Sys.println("zero-null-int-callee");
		return null;
	}

	public static function nullableFlag():Null<Bool> {
		Sys.println("zero-null-bool-callee");
		return true;
	}
}
