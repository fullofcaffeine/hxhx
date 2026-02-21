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

	static function clampMod(v:Int):Int {
		final r = v % 1000003;
		return r < 0 ? r + 1000003 : r;
	}

	static function compute(n:Int):Int {
		var acc = 0;
		var alt = 1;
		var wobble = 17;
		for (i in 0...n) {
			final c = ((i * 13 + 5) % 97) + 1;
			acc = clampMod(acc + (c * (i + 3)));
			alt = clampMod((alt * 7) + (i % 101) + c);
			wobble = clampMod((wobble * 11) + (c % 19) + (i % 7));
			if ((i % 3) == 0) {
				acc = clampMod(acc + alt + wobble);
			} else {
				acc = clampMod(acc - alt + wobble);
			}
		}

		return clampMod(acc + alt + wobble);
	}

	static function main() {
		final n = iterations();
		final value = compute(n);
		Sys.println("bench_iters=" + n);
		Sys.println("bench_result=" + value);
	}
}
