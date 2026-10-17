/** Observe native scalar transfers without changing the nullable source. */
class Main {
	static var stored:Int;
	static var effects:Int = 0;

	static function identity(value:Int):Int
		return value;

	static function returned(value:Null<Int>):Int
		return value;

	static function supplied(value:Null<Int>):Null<Int> {
		effects++;
		return value;
	}

	static function exercise(value:Null<Int>, expected:Int):Void {
		var local:Int = supplied(value);
		if (local != expected)
			throw "local initialization changed";
		local = supplied(value);
		if (local != expected)
			throw "local assignment changed";
		stored = supplied(value);
		if (stored != expected)
			throw "static assignment changed";
		final box = new Box(1);
		box.value = supplied(value);
		if (box.value != expected)
			throw "instance assignment changed";
		final values:Array<Int> = [1];
		values[0] = supplied(value);
		if (values[0] != expected)
			throw "array assignment changed";
		if (identity(supplied(value)) != expected)
			throw "argument transfer changed";
		if (returned(supplied(value)) != expected)
			throw "return transfer changed";
		final constructed = new Box(supplied(value));
		if (constructed.value != expected)
			throw "constructor argument changed";
		if (box.identity(supplied(value)) != expected)
			throw "instance argument changed";
		var captured:Int = 1;
		final update = () -> {
			captured = supplied(value);
		};
		update();
		if (captured != expected)
			throw "captured assignment changed";
		if (expected == 0 && value != null)
			throw "conversion changed nullable source";
		if (expected == 7 && value != 7)
			throw "conversion changed present source";
	}

	static function main():Void {
		exercise(null, 0);
		exercise(7, 7);
		if (effects != 20)
			throw "transfers repeated or skipped source effects";
	}
}

/** Plain Int fields and parameters require scalar values at their native boundaries. */
class Box {
	public var value:Int;

	public function new(value:Int) {
		this.value = value;
	}

	public function identity(value:Int):Int
		return value;
}
