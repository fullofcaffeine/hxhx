/**
	Int modulo by zero, compared with upstream Haxe 4.3.7 on Neko.

	Haxe leaves Int division by zero target-specific. Native Int is a 32-bit
	machine integer and cannot hold eval's NaN result, so it throws a catchable
	exception like the static targets (Neko, JVM, C#) instead of stopping the
	program. Normal modulo values, including negative operands, are unchanged.
**/
class Main {
	static function main() {
		final zero = Std.parseInt("0");
		try {
			Sys.println(7 % zero);
		} catch (e:Dynamic) {
			Sys.println("caught modulo");
		}
		var x = 7;
		try {
			x %= zero;
			Sys.println(x);
		} catch (e:Dynamic) {
			Sys.println("caught compound modulo");
		}
		Sys.println(x);
		Sys.println(7 % 3);
		Sys.println(-7 % 3);
		Sys.println(7 % -3);
	}
}
