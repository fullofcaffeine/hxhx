/** Array creation evaluates elements once, from left to right, in their original scope. */
class Main {
	static var effects = "";

	static function mark(label:String, value:Int):Int {
		effects += label;
		return value;
	}

	static function fail():Int {
		effects += "b";
		throw "stop";
	}

	static function main():Void {
		final values = [mark("a", 1), mark("b", 2), mark("c", 3)];
		Sys.println(effects == "abc");
		Sys.println(values[0] == 1 && values[1] == 2 && values[2] == 3);
		effects = "";
		final nested = [[mark("a", 1), mark("b", 2)], [mark("c", 3)]];
		Sys.println(effects == "abc");
		Sys.println(nested[0][1] == 2 && nested[1][0] == 3);
		final __hxhx_array_values = 7;
		final __hxhx_array_storage = 8;
		final shadowed = [__hxhx_array_values, __hxhx_array_storage];
		Sys.println(shadowed[0] == 7 && shadowed[1] == 8);
		effects = "";
		var rejected = false;
		try {
			final unused = [mark("a", 1), fail(), mark("c", 3)];
		} catch (_:Dynamic) {
			rejected = true;
		}
		Sys.println(rejected && effects == "ab");
	}
}
