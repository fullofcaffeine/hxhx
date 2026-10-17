/** Preserve live aggregate values through conversion callbacks and forced collection. */
class M14CppAggregateStringTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_object_string_seed", mainModule: "AggregateContract", requiredModules: ["Std"]});
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final output = ".tmp/cpp-aggregate-string";
		final result = backend.cpp.CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new backend.BackendContext(output, null, "AggregateContract", true, true, fixture.defines));
		for (index in 0...fixture.modules.length)
			if (CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity() != revisions[index])
				throw "aggregate string conversion changed its authored source";
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "aggregate string conversion assertions failed";
		CppManagedAssertionFixture.sanitizers(output, "CPP_AGGREGATE_STRING", "test/cpp_managed_heap/StringCatchObserver.cpp", "src/AggregateContract.cpp");
		Sys.println("CPP_AGGREGATE_STRING:PASS");
	}
}
