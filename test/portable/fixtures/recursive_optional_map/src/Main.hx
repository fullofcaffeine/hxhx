/** Checks optional Map forwarding within a mutually recursive call group. */
class Main {
	static var reads:Int = 0;

	static function consume(values:Map<String, Int>, depth:Int):Int {
		if (depth == 0) {
			if (values == null)
				return 0;
			values.set("seen", 1);
			return values.get("x");
		}
		return forward(depth - 1, values);
	}

	static function forward(depth:Int, ?values:Map<String, Int>):Int {
		if (depth < 0)
			return consume(["x" => 3], 0);
		return consume(values, depth);
	}

	static function next(values:Map<String, Int>):Map<String, Int> {
		reads++;
		return values;
	}

	static function main():Void {
		Sys.println(forward(0, ["x" => 7]));
		Sys.println(forward(0));
		Sys.println(forward(-1));
		final values = ["x" => 9];
		Sys.println(forward(1, next(values)));
		Sys.println("seen=" + values.get("seen"));
		Sys.println("reads=" + reads);
	}
}
