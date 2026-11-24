import haxe.macro.Expr;
import sys.io.File;

/**
	The parse oracle compares an abstract constructor as authored on both sides.

	Haxe 4.3.7 builds an abstract's constructor as `_new` before build macros run and wraps the
	authored body in `var this:T; ...; return cast this;` (typeloadFields.ml:265-298), so the
	upstream recorder used to record a generated shape under `_new` while hxhx recorded the
	authored `new`: all 19 abstract constructors of the corpus counted as missing. The upstream
	recorder now removes exactly that wrapper and records `new`; hxhx prints an abstract's `new`
	as a block, because the wrapper loses the authored bracing. A plain class named like an
	implementation class keeps its authored `_new`.
**/
class M14ParseOracleAbstractConstructorTest {
	static final root = "test/fixtures/parse_oracle_abstract_constructor";
	static final dump = ".tmp/parse_oracle_abstract_constructor/upstream.json";

	static function expect(label:String, actual:String, expected:String):Void {
		if (actual != expected)
			throw label + ":\nexpected:\n" + expected + "\nactual:\n" + actual;
	}

	static function upstreamRecords():Map<String, String> {
		sys.FileSystem.createDirectory(haxe.io.Path.directory(dump));
		final process = new sys.io.Process("node_modules/.bin/haxe", [
			"-cp",
			"scripts/oracle/upstream",
			"-cp",
			"scripts/oracle/shared",
			"-cp",
			root,
			"-main",
			"Main",
			"--macro",
			"ParseOracleUpstream.install('" + sys.FileSystem.absolutePath(dump) + "')",
			"--no-output"
		]);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0)
			throw "upstream recorder failed: " + stderr;
		final parsed:{records:Array<{key:String, ?body:String}>} = haxe.Json.parse(File.getContent(dump));
		final records = new Map<String, String>();
		for (record in parsed.records)
			if (StringTools.startsWith(record.key, "Main."))
				records.set(record.key, record.body);
		return records;
	}

	public static function main():Void {
		final upstream = upstreamRecords();
		for (key in ["Main.Flags._new", "Main.Pair._new"])
			if (upstream.exists(key))
				throw "the upstream recorder kept the generated constructor " + key;
		expect("upstream Flags.new", upstream.get("Main.Flags.new"), "{\n\tthis = i;\n}");
		expect("upstream Pair.new", upstream.get("Main.Pair.new"), "{\n\tvar total = a + b;\n\tthis = { a : a, b : total };\n}");
		if (!upstream.exists("Main.Lookalike._new"))
			throw "a plain class's authored _new must stay _new";
		Sys.println("PARSE_ORACLE_ABSTRACT_CONSTRUCTOR_UPSTREAM:PASS");

		final path = root + "/Main.hx";
		// The fixture's constructors hold no syntax that authored parsing keeps differently.
		final decl = ParserStage.parse(File.getContent(path), path).getDecl();
		final export = new MacroBodyExport(new MacroSyntaxPositions(path));
		final position:Position = {file: path, min: 0, max: 0};
		var compared = 0;
		for (cls in HxModuleDecl.getClasses(decl))
			for (fn in HxClassDecl.getFunctions(cls))
				if (HxFunctionDecl.getName(fn) == "new" && (HxClassDecl.getName(cls) == "Flags" || HxClassDecl.getName(cls) == "Pair")) {
					final key = "Main." + HxClassDecl.getName(cls) + ".new";
					expect("hxhx " + key, ParseOracleHxhx.functionBody(cls, fn, export, position), upstream.get(key));
					compared++;
				}
		if (compared != 2)
			throw "expected both abstract constructors on the hxhx side, compared " + compared;
		Sys.println("PARSE_ORACLE_ABSTRACT_CONSTRUCTOR_HXHX:PASS");
	}
}
