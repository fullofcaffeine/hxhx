class Main {
	static function main() {
		final parts:Array<String> = [];

		// Body runs at least once, even if condition is initially false.
		{
			var i = 0;
			do {
				parts.push("i" + i);
				i++;
			} while (i < 0);
		}
		final once = parts.join(",");

		// `continue` jumps to the condition check (do-while semantics).
		{
			final xs:Array<String> = [];
			var i = 0;
			do {
				i++;
				if (i == 1)
					continue;
				xs.push("x" + i);
			} while (i < 3);
			parts.push("cont=" + xs.join("|"));
		}

		// `break` exits the loop without evaluating the condition again.
		{
			final xs:Array<String> = [];
			var i = 0;
			do {
				i++;
				if (i == 2)
					break;
				xs.push("b" + i);
			} while (true);
			parts.push("break=" + xs.join("|"));
		}

		// Condition can be `Null<Bool>` and must still be treated as an OCaml `bool`.
		{
			var c:Null<Bool> = true;
			var n = 0;
			do {
				n++;
				c = n < 2;
			} while (c);
			parts.push("nullbool=" + n);
		}

		Sys.println("once=" + once + "," + parts.slice(1).join(","));
	}
}
