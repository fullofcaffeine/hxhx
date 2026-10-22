/** Guarded yields preserve source order and allocate one ordinary runtime array. */
class Main {
	static function input():Array<Int> {
		Sys.println("input");
		return [1, 2, 3];
	}

	static function allow(value:Int):Bool {
		Sys.println("guard" + value);
		return value > 1;
	}

	static function yieldValue(value:Int):Int {
		Sys.println("yield" + value);
		return value * 2;
	}

	static function values():Array<Int> {
		return [for (v in [1, 2, 3]) if (v > 1) v];
	}

	/** The collection stores already boxed values from an ordinary Dynamic return boundary. */
	static function boxed(value:Bool):Dynamic
		return value;

	static function exits():Array<Int> {
		return [
			for (value in [1, 2, 3, 4]) {
				if (value == 2) continue;
				if (value == 4) break;
				value;
			}
		];
	}

	static function returns():Array<Int> {
		return [
			for (value in [1, 2, 3]) {
				if (value == 2) return [9];
				value;
			}
		];
	}

	static function main():Void {
		Sys.println(values().join(","));
		final ordered = [for (value in input()) if (allow(value)) yieldValue(value)];
		Sys.println(ordered.join(","));
		final nested = [for (row in 0...2) for (column in [3, 4]) row * 10 + column];
		Sys.println(nested.join(","));
		final booleans = [for (value in [0, 1]) value == 1];
		Sys.println(booleans[0]);
		Sys.println(booleans[1]);
		final strings = [for (value in ["a", "b"]) value + "!"];
		Sys.println(strings.join(","));
		Sys.println(exits().join(","));
		Sys.println(returns().join(","));
		final erased:Array<Dynamic> = [for (value in [0, 1]) boxed(value == 1)];
		Sys.println(erased[0]);
		Sys.println(erased[1]);
	}
}
