import haxe.macro.Expr;
import sys.io.File;

/**
	Expression metadata keeps upstream syntax in authored parsing; ordinary parsing keeps its
	marker for typing (haxe_ocaml-ac5i9.4).

	Haxe 4.3.7 keeps `@:name(args) expr` and `@name(args) expr` as `EMeta` with the exact name, and
	a call-site `inline f()` as `@:inline f()`. hxhx's marker lost the colon and the export could
	not print it, and the call-site `inline` was dropped. Authored parsing
	(`ParserStage.parseAuthored`) now keeps `HxAuthoredSyntax.META` with the full name, which the
	export prints as `EMeta`; ordinary parsing keeps `__hxhx_expr_meta` and drops `inline`.

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14ExpressionMetadataSyntaxTest {
	static final root = "test/fixtures/expression_metadata_syntax";

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
			throw "expression metadata observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name, true), expected.get(name));
		Sys.println("EXPRESSION_METADATA_AUTHORED:PASS");

		// Ordinary parsing keeps its marker for typing, and still drops the call-site `inline`.
		final decl = ParserStage.parse(source, root + "/Main.hx").getDecl();
		var markers = 0;
		var inlined:Null<Array<HxStmt>> = null;
		for (cls in HxModuleDecl.getClasses(decl))
			for (fn in HxClassDecl.getFunctions(cls)) {
				if (HxFunctionDecl.getName(fn) == "inlined")
					inlined = HxFunctionDecl.getBody(fn);
				for (statement in HxFunctionDecl.getBody(fn))
					if (Std.string(statement).indexOf("__hxhx_expr_meta") >= 0)
						markers++;
			}
		if (markers != 2)
			throw "ordinary parsing must keep __hxhx_expr_meta for both annotated bodies, found " + markers;
		if (inlined == null || Std.string(inlined).indexOf("__hxhx_authored_meta") >= 0)
			throw "ordinary parsing must not keep the authored inline marker";
		Sys.println("EXPRESSION_METADATA_LOWERED:PASS");

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
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([program], []), ".tmp/expression_metadata_syntax");
		observe(executable, [], stdout);
		Sys.println("EXPRESSION_METADATA_NATIVE:PASS");
	}
}
