class Main {
	static var total:Int = 4;
	static var calls:Int = 0;

	static function rhs():Int {
		calls += 1;
		total = 20;
		return 6;
	}

	static function main():Void {
		var value = 2;
		value += 3;
		Sys.println(value);
		Sys.println(value += (value = 10));
		Sys.println(value);
		value -= 4;
		value *= 3;
		Sys.println(value);
		var captured = 5;
		final update = function():Int {
			return captured += (captured = 8);
		};
		Sys.println(update());
		Sys.println(captured);
		Sys.println(total += rhs());
		Sys.println(total);
		Sys.println(calls);
		Sys.println(value += (value *= 2));
		var overflow = 2147483647;
		overflow += 1;
		Sys.println(overflow);
	}
}
