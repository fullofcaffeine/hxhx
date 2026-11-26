import hxhx.CompilationRequestContext;
import hxhx.Stage3Compiler;
import sys.io.File;

/**
	A local inferred from a class type expression reaches the class's static members, as in
	upstream Haxe 4.3.7 (haxe_ocaml-wzpy5). Fixture: `test/fixtures/class_value_alias_static`.

	Upstream types `var s = Something;` as the class's statics, so `s.somefunc()` is a static
	access of `Something` with an Int result. hxhx typed every such access as Dynamic. A local
	marked this way (`TySymbol.getStaticsOwner`) now resolves the static member in typing and in
	the typed-body builder, which builds the same static-method node as `Something.somefunc()`.
	Upstream's JavaScript keeps the receiver (`s.somefunc()`, genjs.ml:705-713); for a plain local
	that holds the class, the static call evaluates the same. Any other receiver, such as a call
	(`getCls().somefunc()`), keeps today's dynamic path, so no computation is skipped.

	- `probe.Alias`: upstream's typed signatures for the five alias forms; hxhx must print the same,
	  and `sideEffectReceiver` stays Dynamic.
	- `Wrong`: upstream rejects static access through a written `Class<Something>`
	  ("Class<Something> has no field somefunc"); only an inferred alias is the class's statics.
	  hxhx keeps today's behavior there (a dynamic access), which this change does not touch.
	- `Main`: built and run on the js-native backend, it must print what upstream prints
	  (`expected.stdout`). The Stage3 OCaml emitter cannot emit a first-class class value
	  (`var s = Something`) on main either ("does not support runtime type operands for first-class
	  type values"), and it is frozen, so the fixture is not run natively.
**/
class M14ClassValueAliasStaticTest {
	static inline final ROOT = "test/fixtures/class_value_alias_static";
	static inline final DUMP = ".tmp/class_value_alias_static/upstream.json";

	/** Upstream Haxe 4.3.7's typed signatures (`TypedOracleUpstream`, interp target). */
	static final EXPECTED = [
		"probe.Alias.Alias.valueOfAlias" => "()->()->Int",
		"probe.Alias.Alias.callThroughValue" => "()->Int",
		"probe.Alias.Alias.callDirect" => "()->Int",
		"probe.Alias.Alias.callWithArgument" => "()->Int",
		"probe.Alias.Alias.staticField" => "()->Int"
	];

	static function main():Void {
		final dump = upstreamDump();
		final upstream = new Map<String, String>();
		for (record in dump.records)
			upstream.set(record.key, record.signature);
		for (key => signature in EXPECTED)
			require(upstream.get(key) == signature, "upstream " + key + ": expected " + signature + ", actual " + upstream.get(key));

		final hxhx = hxhxSignatures(dump.defines);
		for (key => signature in EXPECTED)
			require(hxhx.get(key) == signature, "hxhx " + key + ": expected " + signature + ", actual " + hxhx.get(key));
		require(hxhx.get("probe.Alias.Alias.sideEffectReceiver") == "()->Dynamic",
			"a call receiver must keep today's dynamic path: " + hxhx.get("probe.Alias.Alias.sideEffectReceiver"));

		final wrong = new sys.io.Process("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Wrong", "--interp"]);
		final wrongErrors = wrong.stderr.readAll().toString();
		final wrongCode = wrong.exitCode();
		wrong.close();
		require(wrongCode != 0 && wrongErrors.indexOf("Class<Something> has no field somefunc") >= 0,
			"upstream no longer rejects static access through a written Class<T>:\n" + wrongErrors);

		final expected = run("node_modules/.bin/haxe", ["-cp", ROOT, "-main", "Main", "--interp"], ".");
		require(expected == File.getContent(ROOT + "/expected.stdout"), "the fixture's expected.stdout no longer matches upstream Haxe:\n" + expected);
		final out = ".tmp/m14-class-value-alias-static";
		compile([
			"--hxhx-backend",
			"js-native",
			"--hxhx-no-run",
			"--hxhx-out",
			out + "/js",
			"-cp",
			ROOT,
			"-main",
			"Main",
			"--js",
			out + "/js/out.js"
		]);
		require(run("node", [out + "/js/out.js"], ".") == expected, "js-native output differs from upstream");
		Sys.println("M14_CLASS_VALUE_ALIAS_STATIC:PASS");
	}

	static function hxhxSignatures(definesList:Array<{name:String, value:String}>):Map<String, String> {
		final defines = new haxe.ds.StringMap<String>();
		for (entry in definesList)
			defines.set(entry.name, entry.value);
		final std = stdRoot();
		final path = ROOT + "/probe/Alias.hx";
		final module = new ResolvedModule("probe.Alias", path, ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([ROOT, std + "/eval/_std", std], defines, index);
		loader.markResolvedAlready([module]);
		final typed = TyperStage.typeResolvedModule(module, index, loader, true);
		final out = new Map<String, String>();
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				out.set("probe.Alias." + HxClassDecl.getName(cls.getSourceDeclaration()) + "." + HxFunctionDecl.getName(fn.getSourceDeclaration()),
					@:privateAccess
					TypedOracleHxhx.signature(fn));
		return out;
	}

	static function upstreamDump():{defines:Array<{name:String, value:String}>, records:Array<{key:String, signature:String}>} {
		sys.FileSystem.createDirectory(haxe.io.Path.directory(DUMP));
		final process = new sys.io.Process("node_modules/.bin/haxe", [
			"-cp",
			"scripts/oracle/upstream",
			"-cp",
			ROOT,
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
		return haxe.Json.parse(File.getContent(DUMP));
	}

	static function compile(arguments:Array<String>):Void {
		final request = CompilationRequestContext.server(1);
		final code = Stage3Compiler.runRequest(arguments, request);
		final output = new StringBuf();
		for (event in request.output.events())
			output.add(event.text);
		request.close(code == 0);
		require(code == 0, "hxhx compile failed (" + arguments.join(" ") + "):\n" + output.toString());
	}

	static function run(command:String, arguments:Array<String>, cwd:String):String {
		final process = new sys.io.Process(command, arguments);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		require(code == 0, command + " exited " + code + ": " + stderr);
		return stdout;
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
