import sys.io.File;

/**
	A returned omitted input takes the result that its peer returns choose, as in upstream Haxe
	4.3.7 (haxe_ocaml-catyk).

	Upstream unifies every return value of a method with one result monomorph. So in
	`if (flag) return first; return 5;` the omitted input `first` becomes `Int`, and in
	`if (second == null) return first; return second;` it gets the same `Null<?>` as `second`.
	A `Dynamic` peer binds nothing. hxhx joined the returns' types and left a returned input
	unknown.

	The test checks that upstream still prints `EXPECTED` for the fixture, then that hxhx prints
	the same through the typed oracle's printer. For `inputThenDynamic` only the parameters are
	compared: upstream leaves its result an open monomorph (`?`) where hxhx gives `Dynamic`, a
	separate, parked difference (haxe_ocaml-rten2.4).
**/
class M14ReturnedInputBindingTest {
	static inline final FIXTURE = "test/fixtures/returned_input_binding/src";
	static inline final DUMP = ".tmp/returned_input_binding/upstream.json";

	/** Upstream Haxe 4.3.7's typed signatures for `probe.Returns` (`TypedOracleUpstream`, interp target). */
	static final EXPECTED = [
		"probe.Returns.Returns.nullFallback" => "(first:Null<?>,second:Null<?>)->Null<?>",
		"probe.Returns.Returns.inputThenInt" => "(first:Int,flag:Bool)->Int",
		"probe.Returns.Returns.intThenInput" => "(first:Int,flag:Bool)->Int",
		"probe.Returns.Returns.inputThenNullInt" => "(first:Null<Int>,flag:Bool,other:Null<Int>)->Null<Int>",
		"probe.Returns.Returns.inputThenDynamic" => "(first:?,flag:Bool,other:Dynamic)->?"
	];

	/** Methods whose result differs for a separate reason; only their parameters are compared on the hxhx side. */
	static final PARAMETERS_ONLY = ["probe.Returns.Returns.inputThenDynamic"];

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
		final path = FIXTURE + "/probe/Returns.hx";
		final module = new ResolvedModule("probe.Returns", path,
			ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([FIXTURE, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final hxhx = new Map<String, String>();
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				hxhx.set("probe.Returns." + HxClassDecl.getName(cls.getSourceDeclaration()) + "." + HxFunctionDecl.getName(fn.getSourceDeclaration()),
					@:privateAccess
					TypedOracleHxhx.signature(fn));
		expectRecords("hxhx", hxhx);
		Sys.println("M14_RETURNED_INPUT_BINDING:PASS");
	}

	static function expectRecords(side:String, actual:Map<String, String>):Void {
		for (key => signature in EXPECTED) {
			final parametersOnly = side == "hxhx" && PARAMETERS_ONLY.indexOf(key) >= 0;
			final found = actual.get(key);
			final matches = parametersOnly ? found != null && parameters(found) == parameters(signature) : found == signature;
			require(matches, side + " " + key + ":\nexpected " + signature + "\nactual   " + found);
		}
		for (key in actual.keys())
			require(EXPECTED.exists(key), side + " recorded an unexpected method " + key);
	}

	/** The parameter list of a printed signature `(a:T,b:U)->R`. */
	static function parameters(signature:String):String
		return signature.substring(0, signature.indexOf(")->") + 1);

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
