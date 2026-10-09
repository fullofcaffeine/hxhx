/** Ordinary methods expose loop results without depending on target library output helpers. */
class RootLoops {
	public static function nulls():Int {
		final values:Array<String> = [null, ""];
		var count = 0;
		for (value in values) {
			if (value == null)
				count++;
		}
		return count;
	}

	public static function indexed():Int {
		var total = 0;
		for (key => value in [5, 8]) {
			if (key == 0)
				continue;
			total += key * 100 + value;
		}
		return total;
	}

	public static function nested():Int {
		var total = 0;
		for (outer in [1, 2]) {
			for (inner in [3, 4]) {
				if (inner == 4)
					break;
				total += outer * 10 + inner;
			}
		}
		return total;
	}

	/** Each escaped closure must retain its own iteration, including after collection. */
	public static function captures():Int {
		var first:Void->Int = function():Int {
			return 0;
		};
		var second:Void->Int = function():Int {
			return 0;
		};
		for (value in [1, 2]) {
			if (value == 1)
				first = function():Int {
					return value;
				};
			else
				second = function():Int {
					return value;
				};
		}
		return first() * 10 + second();
	}

	/** Both bounds execute once in source order. */
	public static function range():Int {
		var calls = 0;
		var total = 0;
		for (value in (++calls)...(++calls + 2)) {
			total += value;
		}
		return calls * 100 + total;
	}

	/** Changing the bound variable cannot extend the range or reuse captured cells. */
	public static function rangeCaptures():Int {
		var end = 3;
		var first:Void->Int = function():Int {
			return 0;
		};
		var second:Void->Int = function():Int {
			return 0;
		};
		for (value in 1...end) {
			end = 9;
			if (value == 1)
				first = function():Int {
					return value;
				};
			else
				second = function():Int {
					return value;
				};
		}
		return first() * 10 + second();
	}

	public static function repeated():Int {
		var index = 0;
		var total = 0;
		while (index < 4) {
			index++;
			if (index == 2)
				continue;
			if (index == 4)
				break;
			total += index;
		}
		do {
			total++;
		} while (total < 6);
		return total;
	}

	public static function early():Int {
		for (value in [1, 2, 3]) {
			if (value == 2)
				return value;
		}
		return 99;
	}
}
