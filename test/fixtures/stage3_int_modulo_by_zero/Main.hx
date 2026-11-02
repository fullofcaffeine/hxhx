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
		// Typed clauses tell a catchable Haxe String apart from an untagged native
		// exception that only `catch (e:Dynamic)` would see. Labels, not messages,
		// are printed, because each target words the error differently.
		try {
			Sys.println(7 % zero);
		} catch (e:String) {
			Sys.println("caught modulo as String");
		} catch (e:haxe.Exception) {
			Sys.println("caught modulo as haxe.Exception");
		} catch (e:Dynamic) {
			Sys.println("caught modulo as Dynamic");
		}
		var x = 7;
		try {
			x %= zero;
			Sys.println(x);
		} catch (e:String) {
			Sys.println("caught compound modulo as String");
		} catch (e:Dynamic) {
			Sys.println("caught compound modulo as Dynamic");
		}
		// haxe.Int32 `%` is covered by the portable fixture int_modulo_by_zero only:
		// Stage3 currently lowers Int32 arithmetic wrongly (haxe_ocaml-ah89c).
		Sys.println(x);
		Sys.println(7 % 3);
		Sys.println(-7 % 3);
		Sys.println(7 % -3);
	}
}
