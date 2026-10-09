/** Record startup effects without needing a target I/O binding in the compiled program. */
class Main {
	public static var log:Int;
	public static var wrapA:Int = product(2147483647, 2147483647);
	public static var wrapB:Int = product(-2147483648, -1);
	public static var wrapC:Int = product(-50000, 50000);

	public static function product(left:Int, right:Int):Int {
		return left * right;
	}

	static function __init__():Void {
		log = 1;
	}

	public static function mark(event:Int, value:Int):Int {
		log = log * 10 + event;
		return value;
	}

	public static function main():Void {
		External.marker();
		log = log * 10 + 5;
	}
}

/** A used extern supplies inline source but does not participate in native class startup. */
extern class External {
	public static inline function marker():Int
		return 7;
	static function __init__():Void {
		throw "extern startup must not execute";
	}
}

/** A field dependency moves Beta before both of these authored initializers. */
class Alpha {
	public static var first:Int = Main.mark(3, 1);
	public static var second:Int = Main.mark(4, Beta.value);
}

/** Provide the value read by the earlier declared class. */
class Beta {
	public static var value:Int = Main.mark(2, 2);
}

/** Loading the module retains this effect even though no source method calls this class. */
class Unused {
	public static var value:Int = Main.mark(6, 3);
}
