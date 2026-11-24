import haxe.macro.Expr;
import sys.io.File;

/**
	`return if (c) a else b` keeps upstream syntax in authored parsing and is still rewritten for
	typing (haxe_ocaml-ac5i9.5).

	Haxe 4.3.7 keeps one `EReturn(EIf)`. hxhx rewrote it while parsing into `if (c) return a else
	return b`, so the parse oracle saw a different tree. Authored parsing
	(`ParserStage.parseAuthored`) now parses the `if` as an expression, also in abstract bodies
	that the scanner path re-parses (`HxParser.withAuthoredSyntax`). Ordinary parsing keeps the
	rewrite and its `SIf.valueReturn` marker, which the typer reads.

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14ReturnIfSyntaxTest {
	static final root = "test/fixtures/return_if_syntax";

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
			throw "return if observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name, true), expected.get(name));
		Sys.println("RETURN_IF_AUTHORED:PASS");

		// Ordinary parsing still rewrites the statement into an `if` with a return in each branch.
		expect("lowered clamp", body(source, "clamp", false), "{\n\tvar limit = 10;\n\tif (value > limit) return limit else return value;\n}");
		Sys.println("RETURN_IF_LOWERED:PASS");

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
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/return_if_syntax");
		observe(executable, [], stdout);
		Sys.println("RETURN_IF_NATIVE:PASS");
	}
}
