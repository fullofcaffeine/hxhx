import haxe.macro.Expr;
import sys.io.File;

/**
	`macro e` in code a macro parses, or in a macro argument, is exported as the syntax that
	builds the quoted `Expr`, as upstream's parser writes it (haxe_ocaml-09i7i).

	Upstream reifies a quotation while it parses (`parse_macro_expr` ends in `reify_expr`,
	`src/syntax/grammar.mly` lines 1275-1294 in Haxe 4.3.7).
	`test/fixtures/macro_quotation_export/expected.txt` is upstream's printed parse of each case
	(`Probe.hx`, run with `oracle.hxml`). hxhx parses the same text, exports it as the
	`Context.parseInlineString` service does, prints it with `haxe.macro.Printer`, and must match.
	Position numbers are masked: hxhx gives quoted nodes the positions it records today, and
	exact ranges wait on `haxe_ocaml-9sj5p.2`.
**/
class M14MacroQuotationExportTest {
	static inline final FIXTURE = "test/fixtures/macro_quotation_export";
	static final positionNumbers = ~/min : -?[0-9]+, max : -?[0-9]+/g;

	/** A nested quotation writes the inner positions as data: `{field: "min", expr: <CInt>}`. */
	static final quotedPositionNumbers = ~/field : "(min|max)", expr : \{ expr : EConst\(CInt\("-?[0-9]+"/g;

	static function masked(text:String):String
		return quotedPositionNumbers.replace(positionNumbers.replace(text, "min : _, max : _"), "field : \"$1\", expr : { expr : EConst(CInt(\"_\"");

	static function main():Void {
		final lines = File.getContent(FIXTURE + "/expected.txt").split("\n").filter(line -> line.length > 0);
		if (lines.length == 0 || lines.length % 2 != 0)
			throw "expected.txt must hold pairs of a case and its printed parse";
		final failures = [];
		var index = 0;
		while (index < lines.length) {
			final code = lines[index];
			final upstream = StringTools.trim(lines[index + 1]).substr("=> ".length);
			index += 2;
			final position:Position = {file: "Probe.txt", min: 0, max: 0};
			final exported = new MacroSyntaxExport(new MacroSyntaxPositions("Probe.txt")).quotation(HxParser.parseExprText(code), position);
			final printed = new haxe.macro.Printer().printExpr(exported);
			if (masked(printed) != masked(upstream))
				failures.push(code + "\n  hxhx:     " + printed + "\n  upstream: " + upstream);
		}
		if (failures.length > 0)
			throw failures.length + " quotation(s) differ from upstream:\n" + failures.join("\n");
		Sys.println("M14_MACRO_QUOTATION_EXPORT:PASS");
	}
}
