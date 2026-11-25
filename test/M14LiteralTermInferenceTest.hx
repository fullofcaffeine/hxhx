import sys.io.File;

/**
	An object literal assigned to an untyped local shares its field values' inference variables,
	as in upstream Haxe 4.3.7 (haxe_ocaml-rten2.6).

	Upstream types an object literal as a structure whose fields keep the values' own types,
	including open monomorphs: an omitted parameter, an empty array's element, `null` as
	`Null<?>`. Assigning the literal to `var e = null` binds `e` to that structure, so a later
	`return e` against a written result type binds the parameter too
	(`haxe.macro.MacroStringTools.toFieldExpr`). hxhx kept no term for a literal, so the omitted
	parameter stayed unknown: `(?p:Null<?>)` where upstream prints `(?p:Null<String>)`.

	The test checks that upstream still prints `EXPECTED` for the fixture, then that hxhx prints
	the same through the typed oracle's printer.
**/
class M14LiteralTermInferenceTest {
	static inline final FIXTURE = "test/fixtures/literal_term_inference/src";
	static inline final DUMP = ".tmp/literal_term_inference/upstream.json";

	/** Upstream Haxe 4.3.7's typed signatures for `probe.LiteralTerm` (`TypedOracleUpstream`, interp target). */
	static final EXPECTED = [
		"probe.LiteralTerm.LiteralTerm.structured" => "(?p:Null<String>)->{a:Int,b:String}",
		"probe.LiteralTerm.LiteralTerm.nested" => "(?p:Null<String>)->{inner:{a:Int,b:String}}",
		"probe.LiteralTerm.LiteralTerm.withNull" => "(?p:Null<String>)->{a:Null<Int>,b:String}",
		"probe.LiteralTerm.LiteralTerm.uninitialized" => "(?p:Null<String>)->{a:Int,b:String}",
		"probe.LiteralTerm.LiteralTerm.closed" => "()->{a:Int,b:String}"
	];

	static function main():Void {
		sys.FileSystem.createDirectory(haxe.io.Path.directory(DUMP));
		final process = new sys.io.Process("node_modules/.bin/haxe", [
			"-cp",
			"scripts/oracle/upstream",
			"-cp",
			FIXTURE,
			"--macro",
			"TypedOracleUpstream.install('" + sys.FileSystem.absolutePath(DUMP) + "')",
			"--macro",
			"include('probe', true)",
			"--interp",
			"--no-output"
		]);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, "upstream recorder failed: " + stderr);
		final dump:{defines:Array<{name:String, value:String}>, records:Array<{key:String, signature:String}>} = haxe.Json.parse(File.getContent(DUMP));
		final upstream = new Map<String, String>();
		for (record in dump.records)
			if (StringTools.startsWith(record.key, "probe."))
				upstream.set(record.key, record.signature);
		expectRecords("upstream", upstream);

		final defines = new haxe.ds.StringMap<String>();
		for (entry in dump.defines)
			defines.set(entry.name, entry.value);
		final std = stdRoot();
		final path = FIXTURE + "/probe/LiteralTerm.hx";
		final module = new ResolvedModule("probe.LiteralTerm", path,
			ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([FIXTURE, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final hxhx = new Map<String, String>();
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				hxhx.set("probe.LiteralTerm." + HxClassDecl.getName(cls.getSourceDeclaration()) + "." + HxFunctionDecl.getName(fn.getSourceDeclaration()),
					@:privateAccess
					TypedOracleHxhx.signature(fn));
		expectRecords("hxhx", hxhx);
		Sys.println("M14_LITERAL_TERM_INFERENCE:PASS");
	}

	static function expectRecords(side:String, actual:Map<String, String>):Void {
		for (key => signature in EXPECTED)
			require(actual.get(key) == signature, side + " " + key + ":\nexpected " + signature + "\nactual   " + actual.get(key));
		for (key in actual.keys())
			require(EXPECTED.exists(key), side + " recorded an unexpected method " + key);
	}

	/** CI installs the pinned compiler through Lix; developers may set HAXE_STD_PATH. */
	static function stdRoot():String {
		final configured = Sys.getEnv("HAXE_STD_PATH");
		if (configured != null && configured != "" && sys.FileSystem.isDirectory(configured))
			return haxe.io.Path.removeTrailingSlashes(configured);
		final lixManaged = haxe.io.Path.join([Sys.getEnv("HOME"), "haxe", "versions", "4.3.7", "std"]);
		if (sys.FileSystem.isDirectory(lixManaged))
			return lixManaged;
		throw "Could not locate the Haxe 4.3.7 standard library. Set HAXE_STD_PATH or install that version through Lix.";
	}

	static function require(condition:Bool, message:String):Void {
		if (!condition)
			throw message;
	}
}
