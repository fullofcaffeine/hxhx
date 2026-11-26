import haxe.macro.Expr;
import sys.io.File;

/**
	Extractor patterns export as upstream parses them (haxe_ocaml-ac5i9.13).

	Haxe 4.3.7 parses a case pattern as an expression, so `_.get() => v` is
	`EBinop(OpArrow, <extractor>, <result pattern>)`. hxhx keeps the extractor's left side as source
	text (`PExtractor(text, result)`), and `MacroBodyExport` refused to export it. The export now
	reads the text with the authored parser and writes the same `=>` operation.

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14ExtractorPatternSyntaxTest {
	static final root = "test/fixtures/extractor_pattern_syntax";

	static function body(source:String, name:String):String {
		final path = root + "/Main.hx";
		final decl = ParserStage.parseAuthored(source, path).getDecl();
		final export = new MacroBodyExport(new MacroSyntaxPositions(path));
		final position:Position = {file: path, min: 0, max: 0};
		for (cls in HxModuleDecl.getClasses(decl))
			for (fn in HxClassDecl.getFunctions(cls))
				if (HxFunctionDecl.getName(fn) == name)
					return new haxe.macro.Printer().printExpr(ParseOracleNormalize.expr(export.functionBody(HxFunctionDecl.getBody(fn),
						HxFunctionDecl.getBodyBraced(fn), position)));
		throw "missing function " + name;
	}

	static function expect(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ":\nexpected:\n" + expected + "\nactual:\n" + actual;
	}

	static function observe(command:String, arguments:Array<String>, expected:String):Void {
		final process = new sys.io.Process(Sys.systemName() == "Mac" ? "gtimeout" : "timeout", ["60", command].concat(arguments));
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != expected)
			throw "extractor pattern observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name), expected.get(name));
		Sys.println("EXTRACTOR_PATTERN_AUTHORED:PASS");

		// The fixture is a valid upstream program with these results.
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], File.getContent(root + "/expected.stdout"));
		Sys.println("EXTRACTOR_PATTERN_UPSTREAM_RUN:PASS");
	}
}
