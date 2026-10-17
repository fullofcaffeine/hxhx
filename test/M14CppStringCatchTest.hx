/** Execute authored String/Bool handler order with real providers and forced-collection observers. */
class M14CppStringCatchTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_string_catch_seed",
			mainModule: "Main",
			requiredModules: ["haxe.Exception", "haxe.ValueException", "StringCatch"]
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/cpp-string-catch";
		final result = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "String catch emission changed its authored typed source";
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "String catch source assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_STRING_CATCH", "test/cpp_managed_heap/StringCatchObserver.cpp");
		Sys.println("CPP_STRING_CATCH:PASS");
	}
}
