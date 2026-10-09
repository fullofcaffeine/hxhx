/** Ordinary execution must keep strings distinct from arrows and evaluate grouped map entries. */
class RuntimeMain {
	static function main():Void {
		final plain = [for (item in [1, 2]) item => item + 1];
		final grouped = [for (item in [1, 2]) (item => item + 1)];
		final nested = [for (item in [1, 2]) ((item => item + 1))];
		final strings = [for (item in [1, 2]) ("a=>b")];
		final comments = [for (item in [1, 2]) (item /* => */)];
		if (plain.get(1) != 2 || plain.get(2) != 3 || grouped.get(1) != 2 || grouped.get(2) != 3 || nested.get(1) != 2 || nested.get(2) != 3
			|| strings.join(",") != "a=>b,a=>b" || comments.join(",") != "1,2")
			throw "comprehension behavior differs";
		Sys.println("SOURCE_COMPREHENSION_RUNTIME:PASS");
	}
}
