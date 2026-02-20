class Main {
	static function main() {
		// Mini "compiler-like" work: parse + eval.
		Assert.eqInt(Eval.eval(new Parser("1 + 2 * 3").parse()), 7, "precedence");
		Assert.eqInt(Eval.eval(new Parser("(10 - 3) * 2").parse()), 14, "parens");
		Assert.eqInt(Eval.eval(new Parser("100 / 5 / 2").parse()), 10, "left assoc");

		// Portable stdlib surface smoke: Bytes.
		final b = haxe.io.Bytes.ofString("abc");
		Assert.eqInt(b.length, 3, "bytes length");
		Assert.eqInt(b.get(0), 97, "bytes get (a)");
		b.set(1, 120); // x
		Assert.eqString(b.toString(), "axc", "bytes toString");

		// Temporary stdout hook until Sys/trace is mapped in portable mode.
		untyped __ocaml__("print_endline \"OK mini-compiler\"");
	}
}
