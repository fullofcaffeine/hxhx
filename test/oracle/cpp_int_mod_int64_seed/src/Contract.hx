import haxe.Int64;

/** Keep the original modulo cases and independently observe operand order and count. */
class Contract {
	static var order:Int = 0;

	static function dividend():Int {
		order = order * 10 + 1;
		return 43;
	}

	static function divisor():Int64 {
		order = order * 10 + 2;
		return Int64.ofInt(5);
	}

	static function main():Void {
		if (Int64.toStr(dividend() % divisor()) != "3" || order != 12)
			throw "modulo changed operand order or count";
		@:privateAccess Main.main();
	}
}
