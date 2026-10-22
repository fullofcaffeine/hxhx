/** Observe source order even when a commutative declaration reverses its parameter order. */
class Main {
	public static var effects:Int = 0;
	public static var less:Bool = false;
	public static var sum:Int = 0;
	public static var mixed:Int = 0;
	public static var compound:Int = 0;
	public static var equal:Bool = true;
	public static var negated:Int = 0;

	static function left():Bits {
		effects = effects * 10 + 1;
		return 7;
	}

	static function right():Bits {
		effects = effects * 10 + 2;
		return 5;
	}

	static function scalar():Int {
		effects = effects * 10 + 3;
		return 4;
	}

	public static function main():Void {
		less = left() < right();
		sum = (left() + right() : Int);
		mixed = (scalar() + left() : Int);
		var value:Bits = 3;
		value += right();
		compound = (value : Int);
		var a:Flag = true;
		var b:Flag = false;
		equal = a == b;
		negated = (-value : Int);
	}
}

/** The first three declarations authorize primitive operations; negate has an ordinary selected body. */
abstract Bits(Int) from Int to Int {
	@:op(A < B) private static function compare(left:Bits, right:Bits):Bool;

	@:op(A + B) private static function add(left:Bits, right:Bits):Bits;

	@:op(A + B) @:commutative private static function addScalar(left:Bits, right:Int):Bits;

	@:op(-A) private static function negate(value:Bits):Bits {
		return -(value : Int);
	}
}

/** Exact boolean backing requires its own selected declaration. */
abstract Flag(Bool) from Bool to Bool {
	@:op(A == B) private static function compare(left:Flag, right:Flag):Bool;
}
