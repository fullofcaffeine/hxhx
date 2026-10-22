/** Observe reference conversion at ordinary typed call boundaries. */
class Main {
	public function new() {}

	public function change(values:Array<Dynamic>):Int {
		values[0] = 7;
		return values.length;
	}

	static function changeInts(values:Array<Int>):Int {
		values[0] = 9;
		return values.length;
	}

	static function changeBools(values:Array<Bool>):Bool {
		values[0] = false;
		return values[1];
	}

	static function nullArray(values:Array<Dynamic>):Bool
		return values == null;

	static function ignoreArray(values:Array<Dynamic>):String
		return "ignored";

	static function unchanged(value:Dynamic):Dynamic
		return value;

	static function argument(value:Dynamic):Dynamic {
		Sys.println("argument");
		return value;
	}

	static function ordered(values:Array<Int>, after:Int):Int
		return values[0] + after;

	static function last():Int {
		Sys.println("last");
		return 1;
	}

	static function main():Void {
		var original:Array<Dynamic> = [1, 2];
		var boxed:Dynamic = original;
		var consumer = new Main();
		Sys.println(consumer.change(argument(boxed)));
		Sys.println(original[0]);
		Sys.println(Std.string(boxed));
		var ints = [3, 4];
		var erasedInts:Dynamic = ints;
		Sys.println(Main.changeInts(argument(erasedInts)));
		Sys.println(ints[0]);
		var callback:(Array<Int>) -> Int = changeInts;
		ints[0] = 5;
		Sys.println(callback(erasedInts));
		Sys.println(ints[0]);
		Sys.println(ordered(argument(erasedInts), last()));
		var bools = [true, true];
		var erasedBools:Dynamic = bools;
		Sys.println(changeBools(erasedBools));
		Sys.println(bools[0]);
		Sys.println(Std.string(erasedBools));
		var empty:Dynamic = null;
		Sys.println(nullArray(empty));
		var wrong:Dynamic = 3;
		Sys.println(ignoreArray(wrong));
		Sys.println(unchanged(wrong));
	}
}
