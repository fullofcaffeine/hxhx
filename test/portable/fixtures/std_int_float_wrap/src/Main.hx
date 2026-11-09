/**
	`Std.int` of Floats outside the 32-bit Int range, compiled by the reflaxe.ocaml backend.

	Upstream Haxe 4.3.7 eval (the reference target) truncates toward zero and
	then wraps the result modulo 2^32 into a signed 32-bit Int, so
	`Std.int(4294967295.0)` is -1. Only finite values with |x| < 2^63, plus NaN
	and signed zero, are printed here. For ±Infinity and |x| >= 2^63, eval's
	result depends on the CPU's float-to-int conversion, and upstream targets
	disagree (see README.md), and so does `x / 0` for a non-zero Int `x`. Each
	value is printed in its own statement.
**/
class Main {
	static function show(label:String, value:Float):Void {
		final truncated = Std.int(value);
		Sys.println(label + " " + Std.string(truncated));
	}

	static function main():Void {
		show("nan", Math.NaN);
		show("0.5", 0.5);
		show("-0.5", -0.5);
		show("1.9", 1.9);
		show("-1.9", -1.9);
		show("-0.0", -0.0);
		show("2^31-1", 2147483647.0);
		show("2^31", 2147483648.0);
		show("2^31+0.5", 2147483648.5);
		show("-2^31", -2147483648.0);
		show("-2^31-1", -2147483649.0);
		show("2^32-1", 4294967295.0);
		show("2^32", 4294967296.0);
		show("2^32+1", 4294967297.0);
		show("3e9+0.5", 3000000000.5);
		show("-3e9-0.5", -3000000000.5);
		show("1e10", 1e10);
		show("-1e10", -1e10);
		show("2^53", 9007199254740992.0);
		final wrapped = Std.int(4294967295.0) + 1;
		Sys.println("then Int arithmetic " + Std.string(wrapped));
		// `Std.int(a / b)` with Int operands is a Float division in Haxe.
		final minInt = -2147483647 - 1;
		final minusOne = -1;
		final quotient = Std.int(minInt / minusOne);
		Sys.println("int division overflow " + Std.string(quotient));
		final seven = 7;
		final two = 2;
		final half = Std.int(-seven / two);
		Sys.println("int division truncates " + Std.string(half));
		final zero = 0;
		final undefined = Std.int(zero / zero);
		Sys.println("zero by zero " + Std.string(undefined));
		final unsigned:UInt = 0xFFFFFFFF;
		final fromUnsigned = Std.int(unsigned);
		Sys.println("from UInt " + Std.string(fromUnsigned));
	}
}
