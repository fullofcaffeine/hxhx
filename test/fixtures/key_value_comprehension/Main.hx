/** The same typed cursor supplies values to both a loop and an array comprehension. */
class Main {
	static function main():Void {
		final cursor = new Cursor();
		final values = [for (key => value in cursor) key + value];
		if (values.length != 3 || values[0] != 0 || values[1] != 11 || values[2] != 22 || cursor.reads != 3)
			throw "key/value comprehension yields";
		final closures = [
			for (key => value in new Cursor())
				function():Int {
					return key + value;
				}
		];
		if (closures[0]() != 0 || closures[1]() != 11 || closures[2]() != 22)
			throw "each comprehension closure must retain its own iteration bindings";
	}
}

/** Each next call produces one pair and advances the same observable cursor. */
class Cursor {
	public var reads:Int = 0;

	public function new() {}

	public function hasNext():Bool
		return reads < 3;

	public function next():{key:Int, value:Int} {
		final key = reads++;
		return {key: key, value: key * 10};
	}
}
