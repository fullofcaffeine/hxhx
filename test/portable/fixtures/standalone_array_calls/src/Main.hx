private final words:Array<String> = ["a", "bb"];
private final lengths:Array<Int> = [for (word in words) word.length];

/** Field initializers preserve Array calls and receiver-before-argument effects. */
class Main {
	static final source:Array<Int> = [3, 4];
	static final values:Array<Int> = [for (value in source) value + 1];
	static final events:Array<String> = [];
	static final count:Int = receiver().push(argument());

	static function receiver():Array<Int> {
		events.push("receiver");
		return values;
	}

	static function argument():Int {
		events.push("argument");
		return 9;
	}

	static function main():Void {
		Sys.println(lengths.join(","));
		Sys.println(values.join(","));
		Sys.println(count);
		Sys.println(events.join(","));
	}
}
