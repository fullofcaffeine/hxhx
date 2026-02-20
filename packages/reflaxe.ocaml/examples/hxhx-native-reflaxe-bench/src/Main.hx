class Main {
	static function iterations():Int {
		final raw = Sys.getEnv("HXHX_BENCH_ITERS");
		return switch (raw) {
			case "200000":
				200000;
			case "100000":
				100000;
			case "50000":
				50000;
			case "20000":
				20000;
			case _:
				20000;
		}
	}

	static function compute(n:Int):Int {
		return n;
	}

	static function main() {
		final n = iterations();
		final value = compute(n);
		Sys.println("bench_iters=" + n);
		Sys.println("bench_result=" + value);
	}
}
