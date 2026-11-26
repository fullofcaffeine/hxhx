/**
	A module that starts with a UTF-8 byte-order mark keeps its package (haxe_ocaml-suqx8).

	Haxe 4.3.7's lexer skips byte-order marks at the start of a file before the first token
	(`src/syntax/lexer.ml` `skip_header`). hxhx read the mark as a token, so `package unit;` was not
	the first token and the module landed in the root package. Five of upstream's unit-test files
	start with a mark, `unit/TestMisc.hx` among them.

	The mark is one character (U+FEFF) where strings hold code points, and three bytes
	(EF BB BF) where they hold bytes; the lexer skips either form, only at the start.
**/
class M14ByteOrderMarkTest {
	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}

	static function packageOf(source:String, authored:Bool):String {
		final parsed = authored ? ParserStage.parseAuthored(source, "A.hx") : ParserStage.parse(source, "A.hx");
		return HxModuleDecl.getPackagePath(parsed.getDecl());
	}

	public static function main():Void {
		final mark = String.fromCharCode(0xFEFF);
		final body = "package unit;\nclass A {\n\tstatic function f() return 1;\n}\n";
		for (authored in [false, true]) {
			final label = authored ? "authored" : "ordinary";
			require(packageOf(body, authored) == "unit", label + ": the plain module must keep its package");
			require(packageOf(mark + body, authored) == "unit",
				label
				+ ": a module after a byte-order mark must keep its package, got `"
				+ packageOf(mark + body, authored)
				+ "`");
			require(packageOf(mark + mark + body, authored) == "unit", label + ": repeated marks are skipped too");
		}
		Sys.println("BYTE_ORDER_MARK_PACKAGE:PASS");

		// The mark keeps its place in the source: the first token starts after it.
		final tokens = HxLexer.tokenize(mark + body);
		require(tokens[0].kind.match(TKeyword(KPackage)), "the first token must be `package`, got " + tokens[0].kind);
		require(tokens[0].pos.index == 1, "the first token must start after the mark, at index 1, got " + tokens[0].pos.index);
		// Only the start of a file is a header: a mark later in the text is still read as before.
		final later = HxLexer.tokenize("a" + mark);
		require(later.length == 3 && later[1].kind.match(TOther(0xFEFF)), "a mark after the first token must stay a token: " + later.map(t -> t.kind));
		Sys.println("BYTE_ORDER_MARK_LEXER:PASS");
	}
}
