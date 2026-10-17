import haxe.Int64;

/** Preserve the original output cases and independently check single evaluation. */
class Contract {
	static var calls:Int = 0;

	static function operand():Int64 {
		calls++;
		return Int64.ofInt(42);
	}

	static function main():Void {
		if (Int64.toStr(~operand()) != "-43" || calls != 1)
			throw "complement changed its operand evaluation count";
		@:privateAccess Main.main();
	}
}
