/** Native remainder: exact Int zero divisors throw; nullable operands yield zero. */
class Main {
	static var order:Int = 0;

	static function require(ok:Bool, label:String):Void {
		if (!ok)
			throw label;
	}

	static function left(value:Int):Int {
		order = order * 10 + 1;
		return value;
	}

	static function right(value:Int):Int {
		order = order * 10 + 2;
		return value;
	}

	static function exact(a:Int, b:Int):Int
		return a % b;

	static function nullable(a:Null<Int>, b:Null<Int>):Int {
		final result = a % b;
		return result;
	}

	static function nullableLeft(a:Null<Int>, b:Int):Int
		return a % b;

	static function nullableRight(a:Int, b:Null<Int>):Int
		return a % b;

	static function checkZero(a:Int, b:Int):Void {
		order = 0;
		var caught = false;
		try {
			exact(left(a), right(b));
		} catch (wrong:Bool) {
			throw "wrong Bool handler";
		} catch (error:String) {
			caught = error == "Mod by 0 Error." && order == 12;
			var rethrown = false;
			try {
				throw error;
			} catch (again:String) {
				rethrown = again == error;
			}
			require(rethrown, "remainder assertion 1");
		}
		require(caught, "remainder assertion 2");
	}

	/** An unmatched inner handler must propagate the same operation failure. */
	static function unmatched():Void {
		try {
			exact(left(7), right(0));
		} catch (_:Bool) {
			throw "wrong inner Bool handler";
		}
	}

	static function main():Void {
		order = 0;
		require(exact(left(7), right(3)) == 1 && order == 12, "remainder assertion 3");
		require(exact(-7, 3) == -1, "remainder assertion 4");
		require(exact(7, -3) == 1, "remainder assertion 5");
		require(exact(-7, -3) == -1, "remainder assertion 6");
		require(exact(-2147483648, -1) == 0, "remainder assertion 7");
		checkZero(7, 0);
		checkZero(0, 0);
		order = 0;
		var propagated = false;
		try {
			unmatched();
		} catch (error:String) {
			propagated = error == "Mod by 0 Error." && order == 12;
		}
		require(propagated, "unmatched exception propagation");
		order = 0;
		require(nullable(left(7), right(0)) == 0 && order == 12, "nullable operand order");
		require(nullable(7, 3) == 1, "remainder assertion 8");
		require(nullable(-7, 3) == -1, "remainder assertion 9");
		require(nullable(-2147483648, -1) == 0, "remainder assertion 10");
		require(nullable(null, 3) == 0, "remainder assertion 11");
		require(nullable(7, null) == 0, "remainder assertion 12");
		require(nullable(null, null) == 0, "remainder assertion 13");
		require(nullable(7, 0) == 0, "remainder assertion 14");
		require(nullable(0, 0) == 0, "remainder assertion 15");
		require(nullableLeft(null, 0) == 0, "remainder assertion 16");
		require(nullableLeft(7, 0) == 0, "remainder assertion 17");
		require(nullableRight(7, null) == 0, "remainder assertion 18");
		require(nullableRight(7, 0) == 0, "remainder assertion 19");
	}
}
