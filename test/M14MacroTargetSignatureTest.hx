import sys.io.File;

/**
	A target compile sees a macro function through its target-view signature (haxe_ocaml-q3mio,
	PR B).

	Upstream Haxe 4.3.7 types a macro function's body only in its macro context. A normal compile
	sees the function without a body and rewrites its signature (`typeloadFields.ml`, lines
	1298-1336): an instance macro loses its first argument (the `this` expression), an
	`ExprOf<T>` argument or result becomes `T`, every other written type and every missing type
	becomes `Dynamic`, and defaults are dropped (an argument stays optional only with `?`). A
	written `haxe.PosInfos` is an error. The rule reads the type as written, so an imported bare
	`PosInfos` becomes `Dynamic` instead.

	hxhx typed the declaration as written: `haxe.macro.Compiler.getDefine(key:String)` printed
	`(key:String)->Void` where upstream prints `(key:Dynamic)->Dynamic`. A call still passes
	syntax to the macro, so call checking keeps the written signature (`caller`).

	The test checks that upstream still prints `EXPECTED` for the fixture, then that hxhx prints
	the same through the typed oracle's printer.
**/
class M14MacroTargetSignatureTest {
	static inline final FIXTURE = "test/fixtures/macro_target_signature";
	static inline final DUMP = ".tmp/macro_target_signature/upstream.json";
	static inline final POS_INFOS_MESSAGE = "haxe.PosInfos is not allowed on macro functions, use Context.currentPos() instead";

	/** Upstream Haxe 4.3.7's typed signatures for `probe.MacroView` (`TypedOracleUpstream`, interp target). */
	static final EXPECTED = [
		"probe.MacroView.MacroView.new" => "()->Void",
		"probe.MacroView.MacroView.untypedArgs" => "(x:Dynamic,y:Dynamic)->Dynamic",
		"probe.MacroView.MacroView.constant" => "(key:Dynamic)->Dynamic",
		"probe.MacroView.MacroView.exprOf" => "(e:Int,?k:Null<Int>,n:Dynamic,q:Int)->String",
		"probe.MacroView.MacroView.spellings" => "(a:Bool,b:Dynamic,c:Dynamic,d:Dynamic,e:Dynamic,f:Dynamic)->Dynamic",
		"probe.MacroView.MacroView.generic" => "(e:T)->T",
		"probe.MacroView.MacroView.instance" => "(e:Dynamic,n:Dynamic)->String",
		"probe.MacroView.MacroView.voidResult" => "(e:Dynamic)->Dynamic",
		"probe.MacroView.MacroView.rest" => "(e:Dynamic,rest:Dynamic)->Dynamic",
		"probe.MacroView.MacroView.restDots" => "(e:Dynamic,rest:Dynamic)->Dynamic",
		"probe.MacroView.MacroView.caller" => "()->Void"
	];

	static function main():Void {
		final dump = upstreamDump();
		final upstream = new Map<String, String>();
		for (record in dump.records)
			if (StringTools.startsWith(record.key, "probe."))
				upstream.set(record.key, record.signature);
		expectRecords("upstream", upstream);
		final rejected = runUpstream(FIXTURE + "/posinfos", null);
		require(rejected.code != 0 && rejected.stderr.indexOf("PosInfosView.hx:6: characters 52-65 : " + POS_INFOS_MESSAGE) >= 0,
			"upstream must reject a written haxe.PosInfos on a macro function:\n" + rejected.stderr);

		final defines = new haxe.ds.StringMap<String>();
		for (entry in dump.defines)
			defines.set(entry.name, entry.value);
		final std = stdRoot();

		// A target compile: no macro class path, so macro functions show their target view. Strict
		// typing rejects `caller` if its calls are checked against the target view.
		final target = load(FIXTURE + "/src", "probe/MacroView.hx", std, defines, null);
		final previousStrict = Sys.getEnv("HXHX_TYPER_STRICT");
		Sys.putEnv("HXHX_TYPER_STRICT", "1");
		final typed = try typedSignatures(target) catch (error:TyperError) {
			Sys.putEnv("HXHX_TYPER_STRICT", previousStrict == null ? "" : previousStrict);
			throw "strict typing of the target compile failed: " + error.toString();
		};
		Sys.putEnv("HXHX_TYPER_STRICT", previousStrict == null ? "" : previousStrict);
		expectRecords("hxhx", typed);
		final declarations = target.index.getByFullName("probe.MacroView").getDeclarations();
		final instance = declarations.filter(d -> d.getSignature().getName() == "instance")[0];
		require(instance.getSignature().getArgNames().join(",") == "e,n", "the target view drops an instance macro's first argument");
		require(instance.getMacroSignature().getArgNames().join(",") == "ethis,e,n", "calls keep the written signature of an instance macro");

		// The macro context (a project-macro plugin build) keeps every macro signature as written.
		final macroRoot = FIXTURE + "/src";
		final macroContext = MacroCompilationContext.forMacroClassPaths([macroRoot], [macroRoot, std + "/eval/_std", std]);
		final macroLoaded = load(macroRoot, "probe/MacroView.hx", std, defines, macroContext);
		for (declaration in macroLoaded.index.getByFullName("probe.MacroView").getDeclarations())
			require(declaration.getSignature() == declaration.getMacroSignature(),
				"a macro compile must keep " + declaration.getSignature().getName() + " as written");

		try {
			load(FIXTURE + "/posinfos", "probe/PosInfosView.hx", std, defines, null);
			throw "hxhx must reject a written haxe.PosInfos on a macro function";
		} catch (error:TyperError) {
			require(error.getMessage() == POS_INFOS_MESSAGE, "unexpected message: " + error.getMessage());
			require(error.getPos().getLine() == 6, "the error must point at the written type, not line " + error.getPos().getLine());
		}
		Sys.println("M14_MACRO_TARGET_SIGNATURE:PASS");
	}

	static function expectRecords(side:String, actual:Map<String, String>):Void {
		for (key => signature in EXPECTED)
			require(actual.get(key) == signature, side + " " + key + ":\nexpected " + signature + "\nactual   " + actual.get(key));
		for (key in actual.keys())
			require(EXPECTED.exists(key), side + " recorded an unexpected method " + key);
	}

	static function load(root:String, file:String, std:String, defines:haxe.ds.StringMap<String>,
			macroContext:Null<MacroCompilationContext>):{index:TyperIndex, loader:ModuleLoader, module:ResolvedModule} {
		final path = root + "/" + file;
		final module = new ResolvedModule(haxe.io.Path.withoutExtension(file).split("/").join("."), path,
			ParserStage.parse(HxConditionalCompilation.filterSource(File.getContent(path), defines), path));
		final index = TyperIndex.buildHeaders([module]);
		final loader = new ModuleLoader([root, std + "/eval/_std", std], defines, index, null, true, null, null, macroContext);
		loader.markResolvedAlready([module]);
		return {index: index, loader: loader, module: module};
	}

	static function typedSignatures(loaded:{index:TyperIndex, loader:ModuleLoader, module:ResolvedModule}):Map<String, String> {
		final typed = TyperStage.typeResolvedModule(loaded.module, loaded.index, loaded.loader, true);
		final out = new Map<String, String>();
		for (cls in typed.getTypedClasses())
			for (fn in cls.getFunctions())
				out.set("probe.MacroView."
					+ HxClassDecl.getName(cls.getSourceDeclaration())
					+ "."
					+ HxFunctionDecl.getName(fn.getSourceDeclaration()),
					TypedOracleHxhx.signature(fn));
		return out;
	}

	static function upstreamDump():{defines:Array<{name:String, value:String}>, records:Array<{key:String, signature:String}>} {
		sys.FileSystem.createDirectory(haxe.io.Path.directory(DUMP));
		final result = runUpstream(FIXTURE + "/src", sys.FileSystem.absolutePath(DUMP));
		require(result.code == 0, "upstream recorder failed: " + result.stderr);
		return haxe.Json.parse(File.getContent(DUMP));
	}

	static function runUpstream(root:String, dump:Null<String>):{code:Int, stderr:String} {
		final arguments = ["-cp", "scripts/oracle/upstream", "-cp", root];
		if (dump != null)
			arguments.push("--macro");
		if (dump != null)
			arguments.push("TypedOracleUpstream.install('" + dump + "')");
		for (argument in ["--macro", "include('probe', true)", "--interp", "--no-output"])
			arguments.push(argument);
		final process = new sys.io.Process("node_modules/.bin/haxe", arguments);
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		return {code: code, stderr: stderr};
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
