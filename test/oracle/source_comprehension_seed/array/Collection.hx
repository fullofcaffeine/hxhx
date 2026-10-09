/** A direct native observer checks the same yielded string without library method calls. */
class Collection {
	public static function collect():Array<String> {
		return [for (item in [1, 2]) ("a=>b")];
	}

	/** Rejected iterations must not increment the yield counter. */
	public static function guarded():Array<Int> {
		var checks = 0;
		var yields = 0;
		return [for (item in [1, 2, 3]) if (++checks > 1) (++yields * 10 + checks)];
	}

	/** Each later guard runs only for elements accepted by every earlier guard. */
	public static function chained():Array<Int> {
		var outer = 0;
		var inner = 0;
		var yields = 0;
		return [
			for (item in [1, 2, 3, 4])
				if (++outer > 1) if (++inner > 1)
					(++yields * 100 + outer * 10 + inner)
		];
	}

	/** Escaped functions retain distinct iteration cells after the array is released. */
	public static function captures():Array<Void->Int> {
		return [
			for (item in [1, 2])
				function():Int {
					return item;
				}
		];
	}

	/** Nested loops append to one array in outer-then-inner iteration order. */
	public static function nested():Array<Int> {
		return [for (outer in [1, 2]) for (inner in [3, 4]) (outer * 10 + inner)];
	}

	/** A yield block's return still exits the authored function. */
	public static function early():Array<Int> {
		return [
			for (item in [1, 2]) {
				if (item == 2) return [99];
				item;
			}
		];
	}

	/** Continue skips appending; break leaves the original comprehension loop. */
	public static function exits():Array<Int> {
		return [
			for (item in [1, 2, 3, 4]) {
				if (item == 2) continue;
				if (item == 4) break;
				item;
			}
		];
	}

	/** Array keys are zero-based indices paired with their original elements. */
	public static function indexed():Array<Int> {
		return [for (key => value in [5, 8]) (key * 100 + value)];
	}

	/** Both key and value captures must keep their own iteration's cells. */
	public static function indexedCaptures():Array<Void->Int> {
		return [
			for (key => value in [5, 8])
				function():Int {
					return key * 100 + value;
				}
		];
	}
}
