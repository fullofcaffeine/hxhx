class Main {
	static function main() {
		final args = Sys.args();
		final n = args.length > 0 ? Std.parseInt(args[0]) : 200000;

		final b = new StringBuf();
		for (i in 0...n) {
			b.add("x");
		}

		// Print only the length so we don't benchmark terminal output.
		Sys.println(b.length);
	}
}
