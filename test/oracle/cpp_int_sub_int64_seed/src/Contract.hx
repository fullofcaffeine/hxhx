import haxe.Int64;

/** Preserve original output and independently observe operand order and count. */
class Contract {
	static var order:Int = 0;

	static function base():Int {
		order = order * 10 + 1;
		return 44;
	}

	static function delta():Int64 {
		order = order * 10 + 2;
		return Int64.ofInt(2);
	}

	static function main():Void {
		if (Int64.toStr(base() - delta()) != "42" || order != 12)
			throw "subtraction changed operand order or count";
		@:privateAccess Main.main();
	}
}
