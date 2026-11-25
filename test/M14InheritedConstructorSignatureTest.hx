import sys.io.File;

/**
	A class that declares no constructor gets the typed-oracle record of the constructor it
	inherits, as upstream Haxe 4.3.7 records it (haxe_ocaml-rten2.5).

	Upstream gives such a non-extern class a constructor field: the nearest ancestor's `new` with
	this class's view of the ancestor's type arguments and a Void result (`typeloadFunction.ml`,
	`add_constructor`, lines 183-240). So `class Child<T> extends Parent<Array<T>>` has
	`new(items:Array<T>, ...)`. hxhx's typed classes keep only declared functions, and that stays
	so; the oracle derives the record through `TypedConstructorPath.inheritedSignature`. Extern
	classes, interfaces and classes without an inherited constructor get no record.

	The test checks that upstream still prints `EXPECTED` for the fixture, then that hxhx's
	records (declared functions and derived constructors) are the same.
**/
class M14InheritedConstructorSignatureTest {
	static inline final FIXTURE = "test/fixtures/inherited_constructor/src";
	static inline final DUMP = ".tmp/inherited_constructor/upstream.json";

	/** Upstream Haxe 4.3.7's typed signatures for `probe.Inherited` (`TypedOracleUpstream`, interp target). */
	static final EXPECTED = [
		"probe.Inherited.Parent.new" => "(items:S,count:Int,?label:Null<String>,?scale:Float)->Void",
		"probe.Inherited.Child.new" => "(items:Array<T>,count:Int,?label:Null<String>,?scale:Float)->Void",
		"probe.Inherited.GrandChild.new" => "(items:Array<String>,count:Int,?label:Null<String>,?scale:Float)->Void",
		"probe.Inherited.Own.new" => "()->Void"
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
		final path = FIXTURE + "/probe/Inherited.hx";
		final module = new ResolvedModule("probe.Inherited", path,
			ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([FIXTURE, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final hxhx = new Map<String, String>();
		for (cls in typed.getTypedClasses()) {
			final owner = "probe.Inherited." + HxClassDecl.getName(cls.getSourceDeclaration());
			for (fn in cls.getFunctions())
				hxhx.set(owner + "." + HxFunctionDecl.getName(fn.getSourceDeclaration()), @:privateAccess TypedOracleHxhx.signature(fn));
			final inherited = TypedOracleHxhx.inheritedConstructor(index, cls);
			if (inherited != null)
				hxhx.set(owner + ".new", inherited);
		}
		expectRecords("hxhx", hxhx);
		Sys.println("M14_INHERITED_CONSTRUCTOR_SIGNATURE:PASS");
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
