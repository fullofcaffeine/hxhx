class Main {
	static function join(prefix:String, ...parts:String):String {
		return prefix + ":" + parts.toArray().join(",");
	}

	static function bracket(...parts:String):String {
		return "[" + parts.toArray().join(",") + "]";
	}

	static function describe(...values:Int):String {
		var total = 0;
		for (value in values)
			total += value;
		final first = values.length > 0 ? Std.string(values[0]) : "none";
		return "count=" + values.length + " first=" + first + " total=" + total;
	}

	static function main() {
		Sys.println(join("p"));
		Sys.println(join("p", "a"));
		Sys.println(join("p", "a", "b"));
		Sys.println(bracket());
		Sys.println(bracket("a"));
		Sys.println(bracket("a", "b"));
		Sys.println(describe());
		Sys.println(describe(4));
		Sys.println(describe(1, 2, 3));
	}
}
