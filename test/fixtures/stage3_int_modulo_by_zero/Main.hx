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
		Sys.println(x);
		Sys.println(7 % 3);
		Sys.println(-7 % 3);
		Sys.println(7 % -3);
		int32Modulo();
	}

	/** Keeps operands out of constant folding: Int32 `%` must reach the runtime check. */
	static function int32(value:Int):haxe.Int32 {
		return value;
	}

	static function int(value:Int):Int {
		return value;
	}

	/** Prints one `haxe.Int32` modulo, or the catch clause that handled a zero divisor. */
	static function printInt32Modulo(left:haxe.Int32, right:haxe.Int32):Void {
		try {
			Sys.println(left + " % " + right + " = " + (left % right));
		} catch (e:String) {
			Sys.println(left + " % " + right + " caught as String");
		} catch (e:haxe.Exception) {
			Sys.println(left + " % " + right + " caught as haxe.Exception");
		} catch (e:Dynamic) {
			Sys.println(left + " % " + right + " caught as Dynamic");
		}
	}

	/**
		`haxe.Int32` modulo used to print 0 on Stage3 because the whole operation
		was replaced by a placeholder (haxe_ocaml-lxj68). It shares the Int
		zero-divisor behavior above.
	**/
	static function int32Modulo():Void {
		printInt32Modulo(int32(7), int32(3));
		printInt32Modulo(int32(-7), int32(3));
		printInt32Modulo(int32(7), int32(-3));
		printInt32Modulo(int32(-7), int32(-3));
		printInt32Modulo(int32(-2147483648), int32(7));
		printInt32Modulo(int32(7), int32(0));
		printInt32Modulo(int32(-7), int32(0));
		Sys.println("mixed " + (int32(7) % int(-3)) + " " + (int(-3) % int32(7)));
		try {
			Sys.println(int32(7) % int(0));
		} catch (e:Dynamic) {
			Sys.println("caught Int32 % Int");
		}
		try {
			Sys.println(int(7) % int32(0));
		} catch (e:Dynamic) {
			Sys.println("caught Int % Int32");
		}
		var updated = int32(-17);
		updated %= 5;
		Sys.println("compound " + updated);
		try {
			updated %= int32(0);
			Sys.println(updated);
		} catch (e:Dynamic) {
			Sys.println("caught compound Int32");
		}
	}
}
