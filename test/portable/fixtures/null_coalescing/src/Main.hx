class Main {
	static function main() {
		var a:Null<Int> = null;
		var b:Int = a ?? 2;
		Sys.println("b=" + b);

		a ??= 5;
		Sys.println("a=" + Std.string(a));

		final c = a ??= 6;
		Sys.println("c=" + Std.string(c));

		var nb:Null<Bool> = null;
		final bb:Bool = nb ?? true;
		Sys.println("bb=" + bb);

		nb ??= false;
		Sys.println("nb=" + Std.string(nb));

		var nf:Null<Float> = null;
		final ff:Float = nf ?? 1.5;
		Sys.println("ff=" + ff);

		nf ??= 2.5;
		Sys.println("nf=" + Std.string(nf));

		Sys.println("OK null_coalescing");
	}
}
