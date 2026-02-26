class Main {
	static function main() {
		final args = Sys.args();
		final n = parsePositiveInt(args, 50000);
		final values = new Array<Int>();
		values.resize(n);
		for (i in 0...n) {
			values[i] = i;
		}
		var sum = 0;
		for (value in values) {
			sum += value;
		}
		Sys.println(sum);
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
