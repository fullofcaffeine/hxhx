import haxe.macro.Context;

/**
	Upstream's parsed form of macro quotations (haxe_ocaml-09i7i): text with `macro e` given to
	Context.parseInlineString comes back as the syntax that builds the quoted `Expr`, printed here.
	M14MacroQuotationExportTest compares hxhx's export with expected.txt, position numbers aside.
**/
class Probe {
	public static final CASES = [
		"macro 1",
		"macro \"text\"",
		"macro foo(1, \"a\")",
		"macro a.b",
		"macro $v{x}",
		"macro $i{name}",
		"macro $e{e}",
		"macro macro 1",
		"macro { var a = 1; a; }",
		"macro [1, 2]",
		"macro new String(\"s\")",
		"macro @myMeta 1",
		"macro @:meta null",
		"macro @myMeta(1, \"a\") x",
		"macro @:pos(p) 1",
		"macro $v{(s:String)}",
		"macro $v{(i:Int)}",
		"macro $v{(f:Float)}",
		"macro $v{123i64}"
	];

	static function main() {
		final pos = Context.makePosition({min: 0, max: 0, file: "Probe.txt"});
		for (code in CASES)
			Sys.println(code + "\n  => " + new haxe.macro.Printer().printExpr(Context.parseInlineString(code, pos)));
	}
}
