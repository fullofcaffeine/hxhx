package;

/** Typed source cases used by the array-read planning contract. */
class ArrayReadCases {
	static var events:Array<String> = [];

	static function makeValues():Array<Int> {
		events.push("receiver");
		return [10, 20, 30];
	}

	static function makeIndex():Int {
		events.push("index");
		return 1;
	}

	public static function ordered():Int {
		return makeValues()[makeIndex()];
	}

	public static function assignmentTarget():Int {
		final values = [1, 2];
		values[0] = 4;
		return values[0];
	}

	public static function updateTarget():Int {
		final values = [1, 2];
		values[0]++;
		return values[0];
	}
}
