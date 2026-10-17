/** Execute the exact upstream-backed generic conversion and ordinary virtual dispatch contract. */
class M14CppGenericStringTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_object_string_seed",
			mainModule: "GenericContract",
			requiredModules: ["Std"]
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/cpp-generic-string";
		final prepared = CppResolvedFixture.prepare(fixture);
		M14CppGenericClassValueTransferContract.check(new backend.cpp.CppTypedProgramProjection(prepared));
		final result = backend.cpp.CppTargetCore.emit(prepared, new backend.BackendContext(output, null, "GenericContract", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "generic string conversion changed its authored source";
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "generic string conversion assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_GENERIC_STRING", "test/cpp_managed_heap/UninitializedLocalObserver.cpp", "src/GenericContract.cpp");
		Sys.println("CPP_GENERIC_STRING:PASS");
	}
}
