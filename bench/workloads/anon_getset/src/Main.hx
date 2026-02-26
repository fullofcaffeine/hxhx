typedef Counter = {
	var x:Int;
}

class Main {
	static function main() {
		final args = Sys.args();
		final iterations = parsePositiveInt(args, 300000);
		final counter:Counter = {x: 0};
		for (_ in 0...iterations) {
			counter.x = counter.x + 1;
		}
		Sys.println(counter.x);
	}

	static function parsePositiveInt(args:Array<String>, fallback:Int):Int {
		if (args.length == 0) {
			return fallback;
		}
		final parsed = Std.parseInt(args[0]);
		if (parsed == null || parsed < 0) {
			return fallback;
		}
		return parsed;
	}
}
