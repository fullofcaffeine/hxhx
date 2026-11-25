import haxe.macro.Expr;
import sys.io.File;

/**
	A `case cast Array:` class-value pattern keeps upstream syntax in authored parsing and still
	matches the class for typing (haxe_ocaml-ac5i9.6).

	Haxe 4.3.7 keeps the `ECast` of a `case cast Array:` pattern. hxhx dropped the `cast` while
	parsing. Authored parsing (`ParserStage.parseAuthored`) now marks the pattern
	(`PEnumValue(name, true)`), and the export prints `cast Array`; ordinary parsing keeps the
	plain class-value pattern.

	`expected.bodies.json` holds the bodies upstream's parse recorder
	(`scripts/oracle/upstream/ParseOracleUpstream.hx`) printed for this fixture.
**/
class M14CastPatternSyntaxTest {
	static final root = "test/fixtures/cast_pattern_syntax";

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
			throw "cast pattern observer differs: " + stdout + stderr;
	}

	public static function main():Void {
		final source = File.getContent(root + "/Main.hx");
		final expected:haxe.DynamicAccess<String> = haxe.Json.parse(File.getContent(root + "/expected.bodies.json"));
		for (name in expected.keys())
			expect(name, body(source, name, true), expected.get(name));
		Sys.println("CAST_PATTERN_AUTHORED:PASS");

		// Ordinary parsing keeps the plain class-value pattern.
		final lowered = body(source, "kind", false);
		if (lowered.indexOf("case Array:") < 0 || lowered.indexOf("cast") >= 0)
			throw "ordinary parsing must keep the plain class-value pattern:\n" + lowered;
		Sys.println("CAST_PATTERN_LOWERED:PASS");

		final stdout = File.getContent(root + "/expected.stdout");
		observe("node_modules/.bin/haxe", ["-cp", root, "--run", "Main"], stdout);
		Sys.println("CAST_PATTERN_UPSTREAM_RUN:PASS");
		// No native run: frozen Stage3 cannot emit class-value patterns ("OCaml named pattern requires
		// its exact selected declaration"), on main too. Ordinary parsing of this fixture is unchanged.
	}
}
