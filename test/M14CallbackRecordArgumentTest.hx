/** Accept nested callbacks at Dynamic boundaries without admitting incompatible concrete parameters. */
class M14CallbackRecordArgumentTest {
	static function main():Void {
		for (argument in ["{item: () -> 1}", "[() -> 1]"])
			reject("Int", argument);
		reject("{item: () -> Int}", "{item: () -> true}");
		reject("Array<() -> Int>", "[() -> true]");
		check("ArgumentContract");
		check("RecoveryContract");
		check("Main");
		Sys.println("CALLBACK_RECORD_ARGUMENT:PASS");
	}

	/** The argument-only proof does not replace the complete Dynamic round trip. */
	static function check(main:String):Void {
		final root = "test/oracle/callback_record_argument_seed";
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", main, "--interp"]) != 0)
			throw "upstream callback record contract failed";
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: main, requiredModules: []});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/callback-record-argument-" + main;
		final emitted = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, main, true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "callback record transfer changed its authored source";
		if (!emitted.builtExecutable || Sys.command(emitted.entryPath, []) != 0)
			throw "native callback record contract failed";
		CppManagedAssertionFixture.sanitizers(output, "CALLBACK_RECORD_ARGUMENT:"
			+ main, "test/cpp_managed_heap/UninitializedLocalObserver.cpp",
			"src/"
			+ main
			+ ".cpp");
	}

	/** These inputs are invalid regardless of how their printed type names contain arrows. */
	static function reject(parameter:String, argument:String):Void {
		final source = "class Main { static function use(value:"
			+ parameter
			+ "):Void {} static function main():Void { use("
			+ argument
			+ "); } }";
		final resolved = new ResolvedModule("Main", "Main.hx", ParserStage.parse(source, "Main.hx"));
		var rejected = false;
		try {
			TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		} catch (_:TyperError) {
			rejected = true;
		}
		if (!rejected)
			throw "callback argument accepted incompatible destination " + parameter;
	}
}
