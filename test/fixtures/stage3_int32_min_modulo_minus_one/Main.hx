/**
	`-2147483648 % -1` on native Stage3, compared with upstream Haxe 4.3.7 eval.

	The mathematical result is 0, but the quotient does not fit in 32 bits, so a
	raw x86 division traps. This case stays out of `stage3_int_modulo_by_zero`,
	whose oracle is Neko: Neko's VM dies with SIGFPE here on x86-64 Linux, while
	eval and native OCaml print 0 on x86-64 and arm64.
**/
class Main {
	/** Keeps operands out of constant folding so the runtime operation is exercised. */
	static function int32(value:Int):haxe.Int32 {
		return value;
	}

	static function int(value:Int):Int {
		return value;
	}

	static function main() {
		Sys.println(int32(-2147483648) % int32(-1));
		Sys.println(int32(-2147483648) % int(-1));
		Sys.println(int(-2147483648) % int32(-1));
		Sys.println(int(-2147483648) % int(-1));
	}
}
