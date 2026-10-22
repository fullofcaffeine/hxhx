/** Retry alternatives with independent captures while reusing observed input values. */
class Main {
	static function select(values:Array<Int>):Int {
		return switch values {
			case [item, 2] | [1, item] if (item == 2): item;
			case _: 0;
		};
	}

	static function observed(values:Array<Int>):Int {
		return switch values {
			case [1, item] if ({
				values[1] = 9;
				false;
			}): 100;
			case [1, item]: item;
			case _: -1;
		};
	}

	static function main():Void {
		Sys.println(select([1, 2]));
		Sys.println(select([3, 2]));
		Sys.println(observed([1, 2]));
	}
}
