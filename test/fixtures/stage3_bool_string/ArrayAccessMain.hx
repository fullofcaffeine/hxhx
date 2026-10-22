/** Indexed operations retain their logical element types before target storage is selected. */
class ArrayAccessMain {
	static var flags:Array<Bool> = [true, false];
	static var first:Bool = [true, false][0];

	static function index():Int {
		Sys.println("index");
		return 0;
	}

	static function probe(values:Array<Bool>):Bool {
		final result = values[index()];
		final assigned = values[0] = false;
		Sys.println(assigned);
		Sys.println(values[0]);
		final numbers = [1];
		final updated = receiver(numbers)[index()] += right(numbers);
		Sys.println(updated);
		Sys.println(numbers[0]);
		return result;
	}

	static function receiver(values:Array<Int>):Array<Int> {
		Sys.println("receiver");
		return values;
	}

	static function right(values:Array<Int>):Int {
		Sys.println("right");
		values[0] = 10;
		Sys.println(values[0]);
		return 2;
	}

	/** Dynamic is the indexed receiver boundary under test; the result stays erased. */
	static function erased(values:Dynamic):Dynamic {
		return values[0];
	}

	static function main():Void {
		Sys.println(first);
		Sys.println(probe(flags));
	}
}
