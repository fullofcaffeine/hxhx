/** Preserve runtime-tagged primitive concatenation without evaluating an operand twice. */
class M14CppDynamicStringConcatTest {
	public static function run():Void {
		final root = "test/oracle/managed_string_concat_seed/dynamic";
		if (Sys.command("node_modules/.bin/haxe", ["-cp", root, "-main", "DynamicConcat", "--interp"]) != 0)
			throw "upstream Dynamic concatenation contract failed";
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "DynamicConcat", requiredModules: []});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/dynamic-concat-contract";
		final emitted = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, "DynamicConcat", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "Dynamic concatenation changed its authored source";
		if (!emitted.builtExecutable || Sys.command(emitted.entryPath, []) != 0)
			throw "native Dynamic concatenation contract failed";
		CppManagedAssertionFixture.sanitizers(output, "DYNAMIC_CONCAT", "test/cpp_managed_heap/UninitializedLocalObserver.cpp", "src/DynamicConcat.cpp");
	}
}
