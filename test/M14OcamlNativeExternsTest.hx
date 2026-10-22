import backend.ocaml.Stage3OcamlExternBindings;
import backend.ocaml.Stage3OcamlLocalNames;
import sys.io.File;
import sys.FileSystem;

/** Real host functions, immutable metadata, exact ownership, and pre-output rejection share one contract. */
class M14OcamlNativeExternsTest {
	static function require(value:Bool, message:String):Void {
		if (!value)
			throw message;
	}

	static function reject(action:Void->Void, diagnostic:String):Void {
		try {
			action();
		} catch (error:haxe.Exception) {
			require(error.message.indexOf(diagnostic) >= 0, "unexpected native binding rejection: " + error.message);
			return;
		}
		throw "missing native binding rejection: " + diagnostic;
	}

	static function typed(source:String):TypedModule
		return M14Stage3RuntimeFixture.typeMain({source: source, path: "Main.hx", root: "."});

	static function host(module:TypedModule):TypedClass
		return module.getTypedClasses().filter(owner -> owner.getSemanticInfo().getShortName() == "Host")[0];

	static function mainFunction(module:TypedModule):TypedBackendFunctionProjection
		return module.getBackendProjection().getClasses().filter(owner -> owner.requireSemanticFacts().getDeclaredName() == "Main")[0].getFunctions()[0];

	static function programSource(moduleName:String, memberName:String):String
		return '@:native("'
			+ moduleName
			+ '") extern class Host { @:native("'
			+ memberName
			+ '") public static function count(value:String):Int; } class Main { static function main():Void { Sys.println(Host.count("abc")); } }';

	/** Local typing needs no program index until an extern declaration requests a host binding. */
	static function localTyping():Void {
		final ordinary = TyperStage.typeModule(ParserStage.parse("class Main { static function main():Void { Sys.println(7); } }", "Main.hx"));
		final owner = ordinary.getBackendProjection().getClasses()[0];
		require(!owner.hasSemanticFacts(), "local typing fixture unexpectedly acquired a program index");
		require(!new Stage3OcamlExternBindings([ordinary]).ownsClass(owner), "ordinary class entered native extern admission");
		final executable = EmitterStage.emitToDir(MacroStage.expandProgram([ordinary], []), ".tmp/ocaml_native_extern_local_typing", true);
		M14Stage3RuntimeFixture.observe({command: executable, arguments: [], expected: "7\n"});
		final unindexed = TyperStage.typeModule(ParserStage.parse(programSource("HxString", "length"), "Main.hx"));
		reject(() -> new Stage3OcamlExternBindings([unindexed]), "has no exact semantic facts for Host");
		Sys.println("OCAML_NATIVE_EXTERN_LOCAL_TYPING:PASS");
	}

	/** Metadata is frozen at indexing, while a new source version changes the derived semantic identity. */
	static function ownership():Void {
		final source = programSource("HxString", "length");
		final first = typed(source);
		final second = typed(source);
		final plan = new Stage3OcamlExternBindings([first]);
		final declaration = host(first).getSemanticInfo().getDeclarations()[0];
		require(plan.reference(declaration) == "(HxString.length : string -> int)", "host binding did not select its declaration metadata");
		reject(() -> plan.reference(host(second).getSemanticInfo().getDeclarations()[0]), "exact declaration");
		final fn = mainFunction(first);
		var call:Null<HxExpr> = null;
		TypedBackendSourceWalk.functionDeclaration(fn.getDeclaration(), expression -> {
			final decoded = TypedExactStaticCallSource.decode(expression);
			if (decoded != null && decoded.method == "count")
				call = expression;
		}, _ -> {});
		require(call != null, "fixture lost the exact native call");
		final names = new Stage3OcamlLocalNames(fn.getLocalCatalog(), false, value -> value);
		reject(() -> plan.renderCall(call, mainFunction(second), null, _ -> "unused", names), "foreign function projection");
		final copied:HxExpr = switch call {
			case ECall(callee, arguments): ECall(callee, arguments.copy());
			case _: throw "native fixture requires a call marker";
		};
		reject(() -> plan.renderCall(copied, fn, null, _ -> "unused", names), "exact typed call");
		final facts = new TypedBackendClassSemanticFacts(host(first).getSemanticInfo(), null, []);
		final original = facts.getCanonicalIdentity();
		final originalRevision = CompilerTypedModuleRevision.fromTypedModule(first).getCanonicalIdentity();
		for (revision in [
			typed(programSource("Stdlib.String", "length")),
			typed(programSource("HxString", "charAt"))
		]) {
			require(new TypedBackendClassSemanticFacts(host(revision).getSemanticInfo(), null, []).getCanonicalIdentity() != original,
				"native metadata change reused the old semantic facts");
			require(CompilerTypedModuleRevision.fromTypedModule(revision).getCanonicalIdentity() != originalRevision,
				"native metadata change reused the old program revision");
		}
		HxClassDecl.getMetadata(host(first).getSourceDeclaration()).push('@:native("Mutated")');
		HxFunctionDecl.getMetadata(declaration.getSourceDeclaration()).push('@:native("mutated")');
		declaration.getMetadata().push('@:native("also_mutated")');
		require(plan.reference(declaration) == "(HxString.length : string -> int)" && facts.getCanonicalIdentity() == original,
			"source metadata mutation changed an indexed native name");
		switch call {
			case ECall(_, arguments):
				arguments[arguments.length - 1] = EString("mutated");
			case _:
		}
		reject(() -> plan.renderCall(call, fn, null, _ -> "unused", names), "mutated");
		Sys.println("OCAML_NATIVE_EXTERN_OWNERSHIP:PASS");
	}

	/** Unsafe target text and unsupported representations fail before replacing the last output. */
	static function admission():Void {
		final root = ".tmp/ocaml_native_extern_rejection";
		FileSystem.createDirectory(root);
		File.saveContent(root + "/Main.ml", "previous native output\n");
		final entries = FileSystem.readDirectory(root).length;
		for (entry in [
			{source: programSource("HxString; bad", "length"), diagnostic: "literal module path"},
			{source: programSource("HxString", "length; bad"), diagnostic: "literal value name"},
			{source: programSource("HxString", "match"), diagnostic: "literal value name"},
			{
				source: '@:native("HxString") extern class Host { public static function count(value:Dynamic):Int; } class Main { static function main():Void { Host.count("abc"); } }',
				diagnostic: "fixed native argument"
			},
			{
				source: '@:native("HxString") extern class Host { public static function count(?value:String):Int; } class Main { static function main():Void { Host.count("abc"); } }',
				diagnostic: "fixed native argument"
			},
			{
				source: '@:native("Stdlib.Fun") extern class Host { @:native("id") public static function value(value:Null<Float>):Float; } class Main { static function main():Void { Host.value(1.25); } }',
				diagnostic: "fixed native argument"
			},
			{
				source: '@:native("Stdlib.Fun") extern class Host { @:native("id") public static function value(?value:Float):Float; } class Main { static function main():Void { Host.value(1.25); } }',
				diagnostic: "fixed native argument"
			}
		]) {
			reject(() -> new backend.ocaml.OcamlTargetCore().emit(MacroStage.expandProgram([typed(entry.source)], []),
				new backend.BackendContext(root, null, "Main", true, false, HxDefineMap.fromRawDefines(["ocaml_profile=portable"]))),
				entry.diagnostic);
			require(File.getContent(root + "/Main.ml") == "previous native output\n" && FileSystem.readDirectory(root).length == entries,
				"rejected native binding changed output");
		}
		Sys.println("OCAML_NATIVE_EXTERN_ADMISSION:PASS");
	}

	static function main():Void {
		localTyping();
		ownership();
		admission();
		final root = "test/fixtures/ocaml_native_externs";
		final expected = File.getContent(root + "/expected.stdout");
		M14Stage3RuntimeFixture.observe({command: "node_modules/.bin/haxe", arguments: ["-cp", root, "--run", "Oracle"], expected: expected});
		final module = M14Stage3RuntimeFixture.typeMain({source: File.getContent(root + "/Main.hx"), path: root + "/Main.hx", root: root});
		final output = ".tmp/ocaml_native_externs";
		final result = new backend.ocaml.OcamlTargetCore().emit(MacroStage.expandProgram([module], []),
			new backend.BackendContext(output, null, "Main", true, true, HxDefineMap.fromRawDefines(["ocaml_profile=portable"])));
		require(result.builtExecutable, "native binding fixture was not built");
		M14Stage3RuntimeFixture.observe({command: result.entryPath, arguments: [], expected: expected});
		for (name in ["Main_HostString.ml", "Main_HostSys.ml", "Main_Nested.ml", "Main_HostStack.ml"])
			require(!FileSystem.exists(output + "/" + name), "native extern emitted a placeholder module: " + name);
		// This real export takes an extra unit argument. A wrong Haxe declaration
		// must be caught by the native checker before an erased println can hide it.
		final mismatch = ".tmp/ocaml_native_extern_abi";
		new backend.ocaml.OcamlTargetCore().emit(MacroStage.expandProgram([typed(programSource("HxString", "toUpperCase"))], []),
			new backend.BackendContext(mismatch, null, "Main", true, false, HxDefineMap.fromRawDefines(["ocaml_profile=portable"])));
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final check = new sys.io.Process(timeout, [
			"30",
			"ocamlc",
			"-I",
			output + "/runtime",
			"-I",
			output,
			"-c",
			mismatch + "/Main.ml"
		]);
		final stdout = check.stdout.readAll().toString();
		final stderr = check.stderr.readAll().toString();
		final code = check.exitCode();
		check.close();
		require(code != 0 && stdout == "" && stderr.indexOf("unit -> string") >= 0 && stderr.indexOf("int") >= 0,
			"native checker did not reject the false host signature: " + stderr);
		Sys.println("OCAML_NATIVE_EXTERN_RUNTIME:PASS");
	}
}
