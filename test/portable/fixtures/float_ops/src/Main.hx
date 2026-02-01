class Main {
	static function main() {
		Sys.println("div=" + (1 / 2));

		final mixAdd:Float = 1.5 + 2;
		Sys.println("mix_add=" + mixAdd);

		final mul = 1.5 * 2;
		Sys.println("mul=" + mul);

		final rem = 5.5 % 2;
		Sys.println("mod=" + rem);

		var x:Float = 1;
		x += 2;
		Sys.println("addAssign=" + x);

		x /= 2;
		Sys.println("divAssign=" + x);

		Sys.println("OK float_ops");
	}
}
