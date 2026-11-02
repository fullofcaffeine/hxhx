/**
	`Math.floor`, `Math.ceil`, `Math.round`, `Math.ffloor`, `Math.fceil`, and `Math.fround`.

	Upstream Haxe 4.3.7 eval (the reference target) returns the Int results as
	`Int32.of_float (mod_float r 2147483648.0)`, where `r` is the Float floor,
	ceil, or round. So `Math.floor(2^31)` is 0 and `Math.floor(1e10)` is
	1410065408. That is not the `Std.int` rule. The Float variants return the
	unbounded Float result. They are checked against the expected value in the
	table, including NaN, the infinities, and the sign of zero, because
	native printing of whole-number Floats differs (Bead haxe_ocaml-iffj5).
	See README.md for the target differences.
**/
class Main {
	static function same(actual:Float, expected:Float):Bool {
		if (Math.isNaN(expected))
			return Math.isNaN(actual);
		if (expected == 0)
			return actual == 0 && (1 / actual < 0) == (1 / expected < 0);
		return actual == expected;
	}

	static function check(name:String, actual:Float, expected:Float):String {
		return same(actual, expected) ? "" : " " + name + "-mismatch";
	}

	static function row(label:String, value:Float, ffloor:Float, fceil:Float, fround:Float):Void {
		final floor = Math.floor(value);
		final ceil = Math.ceil(value);
		final round = Math.round(value);
		final floats = check("ffloor", Math.ffloor(value), ffloor) + check("fceil", Math.fceil(value), fceil) + check("fround", Math.fround(value), fround);
		Sys.println(label + " floor=" + Std.string(floor) + " ceil=" + Std.string(ceil) + " round=" + Std.string(round)
			+ (floats == "" ? " floats=ok" : floats));
	}

	static function main():Void {
		row("nan", Math.NaN, Math.NaN, Math.NaN, Math.NaN);
		row("+inf", Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY, Math.POSITIVE_INFINITY);
		row("-inf", Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY, Math.NEGATIVE_INFINITY);
		row("0.5", 0.5, 0.0, 1.0, 1.0);
		row("-0.5", -0.5, -1.0, -0.0, 0.0);
		row("1.5", 1.5, 1.0, 2.0, 2.0);
		row("-1.5", -1.5, -2.0, -1.0, -1.0);
		row("2.5", 2.5, 2.0, 3.0, 3.0);
		row("-2.5", -2.5, -3.0, -2.0, -2.0);
		row("1.9", 1.9, 1.0, 2.0, 2.0);
		row("-1.9", -1.9, -2.0, -1.0, -2.0);
		row("-0.0", -0.0, -0.0, -0.0, 0.0);
		row("2^31-1", 2147483647.0, 2147483647.0, 2147483647.0, 2147483647.0);
		row("2^31-0.5", 2147483646.5, 2147483646.0, 2147483647.0, 2147483647.0);
		row("2^31", 2147483648.0, 2147483648.0, 2147483648.0, 2147483648.0);
		row("2^31+0.5", 2147483648.5, 2147483648.0, 2147483649.0, 2147483649.0);
		row("-2^31", -2147483648.0, -2147483648.0, -2147483648.0, -2147483648.0);
		row("-2^31-0.5", -2147483648.5, -2147483649.0, -2147483648.0, -2147483648.0);
		row("-2^31-1", -2147483649.0, -2147483649.0, -2147483649.0, -2147483649.0);
		row("2^32-1", 4294967295.0, 4294967295.0, 4294967295.0, 4294967295.0);
		row("2^32", 4294967296.0, 4294967296.0, 4294967296.0, 4294967296.0);
		row("2^32+1", 4294967297.0, 4294967297.0, 4294967297.0, 4294967297.0);
		row("3e9+0.5", 3000000000.5, 3000000000.0, 3000000001.0, 3000000001.0);
		row("-3e9-0.5", -3000000000.5, -3000000001.0, -3000000000.0, -3000000000.0);
		row("1e10", 1e10, 10000000000.0, 10000000000.0, 10000000000.0);
		row("-1e10", -1e10, -10000000000.0, -10000000000.0, -10000000000.0);
		row("2^53", 9007199254740992.0, 9007199254740992.0, 9007199254740992.0, 9007199254740992.0);
		row("1e20", 1e20, 1e+20, 1e+20, 1e+20);
		row("-1e20", -1e20, -1e+20, -1e+20, -1e+20);
	}
}
