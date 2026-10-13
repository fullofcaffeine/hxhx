/** A declared primitive operation evaluates its source once and keeps the abstract's integer storage. */
class Main {
	public static var calls:Int = 0;
	public static var result:Int = 0;
	public static var minimum:Int = 0;
	public static var maximum:Int = 0;
	public static var zero:Int = 0;
	public static var negativeOne:Int = 0;
	public static var inverted:Bool = false;

	static function fresh():Bits {
		calls++;
		return 7;
	}

	public static function main():Void {
		result = (~fresh() : Int);
		minimum = ~(-2147483647 - 1);
		maximum = ~2147483647;
		zero = ~0;
		negativeOne = ~(-1);
		var flag:Flag = false;
		inverted = (!flag : Bool);
	}
}

/** The bodyless declaration selects integer complement; it is not an authored cast. */
abstract Bits(Int) from Int to Int {
	@:op(~A) private function complement():Bits;
}

/** Logical negation uses the same selected-declaration proof for boolean storage. */
abstract Flag(Bool) from Bool to Bool {
	@:op(!A) private function invert():Flag;
}
