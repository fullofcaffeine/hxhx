import haxe.Int64;

/** Keep the original output cases and independently observe both operand orders. */
class Contract {
	static var order:Int = 0;

	static function base():Int64 {
		order = order * 10 + 1;
		return Int64.ofInt(40);
	}

	static function delta():Int {
		order = order * 10 + 2;
		return 2;
	}

	static function main():Void {
		if (Int64.toStr(base() + delta()) != "42" || order != 12)
			throw "right-delta addition changed operand order or count";
		order = 0;
		if (Int64.toStr(delta() + base()) != "42" || order != 21)
			throw "left-delta addition changed operand order or count";
		@:privateAccess Main.main();
	}
}
