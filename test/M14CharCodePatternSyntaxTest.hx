import haxe.macro.Expr;
import sys.io.File;

/**
	A `case "x".code:` pattern keeps upstream syntax in authored parsing and still matches the
	code for typing (haxe_ocaml-ac5i9.3).

	Haxe 4.3.7 keeps the field access `"x".code` in a case pattern. hxhx folded it to an Int
	pattern while parsing, so the parse oracle saw `case 97:`. Authored parsing
	(`ParserStage.parseAuthored`) now records the string on the pattern (`PInt(code, text)`), and
	the export prints `"x".code`; ordinary parsing keeps the plain Int pattern.

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14CharCodePatternSyntaxTest {
	static final root = "test/fixtures/char_code_pattern_syntax";

	static function body(source:String, name:String, authored:Bool):String {
		final path = root + "/Main.hx";
		final decl = (authored ? ParserStage.parseAuthored(source, path) : ParserStage.parse(source, path)).getDecl();
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
			throw "char code pattern observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name, true), expected.get(name));
		Sys.println("CHAR_CODE_PATTERN_AUTHORED:PASS");

		// Ordinary parsing keeps the folded Int pattern.
		final lowered = body(source, "classify", false);
		if (lowered.indexOf("case 97:") < 0 || lowered.indexOf(".code") >= 0)
			throw "ordinary parsing must keep the Int pattern:\n" + lowered;
		Sys.println("CHAR_CODE_PATTERN_LOWERED:PASS");

		final stdout = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], stdout);
		final module = new ResolvedModule("Main", root + "/Main.hx", ParserStage.parse(source, root + "/Main.hx"));
		final arguments = hxhx.Stage1Compiler.Stage1Args.parse(["-cp", root, "-main", "Main"], true);
		final standardRoot = haxe.io.Path.removeTrailingSlashes(hxhx.Stage1Compiler.Stage1Args.getStandardLibraryRoot(arguments));
		final defines = new haxe.ds.StringMap<String>();
		for (name in ["eval", "interp", "sys", "haxe4"])
			defines.set(name, "1");
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([root, standardRoot + "/eval/_std", standardRoot], defines, index);
		loader.markResolvedAlready([module]);
		final program = TyperStage.typeResolvedModule(module, index, loader, true);
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/char_code_pattern_syntax");
		observe(executable, [], stdout);
		Sys.println("CHAR_CODE_PATTERN_NATIVE:PASS");
	}
}
