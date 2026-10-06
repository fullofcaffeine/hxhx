/** Prove implicit instance dispatch, native null results, and receiver lifetime with real providers. */
class M14CppInstanceStringTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_object_string_seed",
			mainModule: "InstanceContract",
			requiredModules: ["Std", "haxe.ValueException"]
		});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/cpp-instance-string";
		final result = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, "InstanceContract", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "instance conversion changed its authored source";
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "instance conversion source assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_INSTANCE_STRING", "test/cpp_managed_heap/StringCatchObserver.cpp", "src/InstanceContract.cpp");
		Sys.println("CPP_INSTANCE_STRING:PASS");
	}
}
