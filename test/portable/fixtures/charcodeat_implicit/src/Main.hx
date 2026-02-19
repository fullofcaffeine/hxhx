class Main {
	static inline function isSpace(c:Int):Bool {
		return c == 32 || c == 9 || c == 10 || c == 13;
	}

	static function main() {
		final s = "  7";

		var i = 0;
		while (i < s.length && isSpace(s.charCodeAt(i))) {
			i = i + 1;
		}

		Sys.println("i=" + i);

		final c = s.charCodeAt(i);
		final digit = c - 48;
		Sys.println("digit=" + digit);

		final kind = switch (c) {
			case 55: "seven";
			default: "other";
		}
		Sys.println("kind=" + kind);

		final oob = s.charCodeAt(999);
		Sys.println("oob_sub=" + (oob - 48));

		final oobKind = switch (oob) {
			case 0: "zero";
			default: "default";
		}
		Sys.println("oob_switch=" + oobKind);

		Sys.println("OK charcodeat_implicit");
	}
}
