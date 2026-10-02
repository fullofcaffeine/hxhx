/** Header conversions retain the storage selected by each applied type argument. */
abstract Box<T>(T) from T to T {}

/** Generic input and output conversions must preserve values and argument effects. */
class Main {
	static function produce():Int {
		Sys.println("argument");
		return 7;
	}

	static function integer(value:Box<Int>):Int {
		return value;
	}

	static function text(value:Box<String>):String {
		return value;
	}

	static function main():Void {
		Sys.println(integer(produce()));
		Sys.println(text("text"));
	}
}
