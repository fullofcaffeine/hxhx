/**
	`Math.pow` and `Math.log` on the Stage3 native route, including IEEE special values.

	Each result is classified (nan, +inf, -inf, -0, 0) or compared with an
	exactly representable expected value, because native printing of
	whole-number Floats differs (Bead haxe_ocaml-iffj5) and inexact results
	can differ in the last bit between C math libraries.
**/
class Main {
	static function classify(x:Float):String {
		if (Math.isNaN(x))
			return "nan";
		if (!Math.isFinite(x))
			return x > 0 ? "+inf" : "-inf";
		if (x == 0)
			return 1 / x < 0 ? "-0" : "0";
		return "finite";
	}

	static function pow(label:String, base:Float, exponent:Float, expected:Float):Void {
		final actual = Math.pow(base, exponent);
		report("pow(" + label + ")", actual, expected);
	}

	static function log(label:String, value:Float, expected:Float):Void {
		final actual = Math.log(value);
		report("log(" + label + ")", actual, expected);
	}

	static function report(label:String, actual:Float, expected:Float):Void {
		final kind = classify(actual);
		final matches = kind == classify(expected) && (kind != "finite" || actual == expected);
		Sys.println(label + " " + kind + (matches ? " ok" : " mismatch"));
	}

	static function main():Void {
		final nan = Math.NaN;
		final inf = Math.POSITIVE_INFINITY;
		pow("2, 3", 2, 3, 8);
		pow("2, -1", 2, -1, 0.5);
		pow("-2, 3", -2, 3, -8);
		pow("-2, 2", -2, 2, 4);
		pow("2.5, 2", 2.5, 2, 6.25);
		pow("0, 0", 0, 0, 1);
		pow("nan, 0", nan, 0, 1);
		pow("1, nan", 1, nan, 1);
		pow("nan, 1", nan, 1, nan);
		pow("-8, 1/3", -8, 1 / 3, nan);
		pow("0, -1", 0, -1, inf);
		pow("-0, -1", -0.0, -1, -inf);
		pow("-0, 3", -0.0, 3, -0.0);
		pow("+inf, -1", inf, -1, 0);
		pow("-inf, 3", -inf, 3, -inf);
		pow("-inf, 2", -inf, 2, inf);
		pow("0.5, +inf", 0.5, inf, 0);
		pow("-1, +inf", -1, inf, 1);
		pow("10, 309", 10, 309, inf);
		// Int arguments reach the Float parameters.
		final three = 3;
		final cube = Math.pow(three, three);
		report("pow(Int 3, Int 3)", cube, 27);
		final one = 1;
		report("log(Int 1)", Math.log(one), 0);
		final half = Math.pow(2, 0.5);
		Sys.println("pow(2, 0.5) squared near 2 " + Std.string(Math.abs(half * half - 2) < 1e-15));
		log("1", 1, 0);
		log("0", 0, -inf);
		log("-0", -0.0, -inf);
		log("-1", -1, nan);
		log("+inf", inf, inf);
		log("nan", nan, nan);
		final e = Math.log(Math.exp(1));
		Sys.println("log(e) near 1 " + Std.string(Math.abs(e - 1) < 1e-15));
	}
}
