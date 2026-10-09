/** Execute independently specified joins through native generation and collecting sanitizer profiles. */
class M14CppArrayJoinTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_array_join_seed", mainModule: "Main", requiredModules: ["Array"]});
		final output = ".tmp/cpp-array-join";
		final boundary = M14CppArrayJoinBoundary.header(new backend.cpp.CppTypedProgramProjection(new MacroExpandedProgram(fixture.modules, false)));
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram(fixture.modules, false),
			new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "native Array.join assertions failed";
		sys.io.File.saveContent(output + "/JoinBoundary.hpp", boundary);
		CppManagedAssertionFixture.sanitizers(output, "CPP_ARRAY_JOIN", "test/cpp_managed_heap/ArrayJoinObserver.cpp");
		Sys.println("CPP_ARRAY_JOIN:PASS");
	}
}
