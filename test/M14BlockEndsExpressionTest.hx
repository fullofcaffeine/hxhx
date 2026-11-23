import haxe.macro.Expr;
import sys.io.File;

/**
	A block ends its expression in ordinary parsing, as in Haxe 4.3.7.

	Upstream continues an expression after `{ ... }` only when the braces are an object literal
	(grammar.mly:1388-1390). hxhx applied postfix operations to a block, so in
	`if (flag) { x = 2; }` followed by a line `(flag ? "a" : "b") + x;` the parenthesized line
	became a call of the block: the switch case lost its value and hxhx rejected the valid program
	("Missing return: String"; haxe.macro.Printer.printTypeDefinition has this shape).

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14BlockEndsExpressionTest {
	static final root = "test/fixtures/block_ends_expression";

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
			throw "block ends expression observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name, false), expected.get(name));
		Sys.println("BLOCK_ENDS_EXPRESSION_PARSE:PASS");

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
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/block_ends_expression");
		observe(executable, [], stdout);
		Sys.println("BLOCK_ENDS_EXPRESSION_NATIVE:PASS");
	}
}
