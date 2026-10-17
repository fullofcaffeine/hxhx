/** The first applicable operator must win even when a later one needs fewer conversions. */
abstract Number(Int) from Int {
	@:op(A / B) public static function general(left:Number, right:Number):String
		return "general";

	@:op(A / B) public static function specific(left:Int, right:Number):String
		return "specific";
}

/** Selection must preserve source operand order and evaluate each operand once. */
class Main {
	static var order:Int = 0;

	static function left():Int {
		order = order * 10 + 1;
		return 4;
	}

	static function right():Number {
		order = order * 10 + 2;
		return 2;
	}

	static function main():Void {
		if (left() / right() != "general" || order != 12)
			throw "operator selection or operand evaluation changed";
	}
}
