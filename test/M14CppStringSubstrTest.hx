/** Prove exact String call ownership, authored effects and native substring behavior together. */
class M14CppStringSubstrTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/fixtures/cpp_string_substr_seed", mainModule: "Main", requiredModules: ["String"]});
		Sys.println("CPP_STRING_SUBSTR:LOADED modules=" + fixture.modules.length);
		final revisions = [
			for (module in fixture.modules)
				CompilerTypedModuleRevision.fromTypedModule(module).getCanonicalIdentity()
		];
		final program = CppResolvedFixture.prepare(fixture);
		Sys.println("CPP_STRING_SUBSTR:PREPARED");
		final boundary = M14CppStringSubstrBoundary.header(new backend.cpp.CppTypedProgramProjection(program));
		Sys.println("CPP_STRING_SUBSTR:BOUNDARY_CHECKED");
		final output = ".tmp/cpp-string-substr";
		backend.cpp.CppTargetCore.emit(program, new backend.BackendContext(output, null, "Main", false, fixture.defines));
		sys.io.File.saveContent(output + "/SubstrBoundary.hpp", boundary);
		for (index in 0...fixture.modules.length)
			if (revisions[index] != CompilerTypedModuleRevision.fromTypedModule(fixture.modules[index]).getCanonicalIdentity())
				throw "substring emission changed its authored typed source";
		Sys.println("CPP_STRING_SUBSTR:EMITTED");
		CppManagedAssertionFixture.sanitizers(output, "CPP_STRING_SUBSTR", "test/cpp_managed_heap/StringSubstrObserver.cpp");
		Sys.println("CPP_STRING_SUBSTR:PASS");
	}
}
