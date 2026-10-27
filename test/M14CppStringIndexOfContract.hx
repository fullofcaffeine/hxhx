/** Prove typed search ownership and operand lifetimes through native execution. */
function run():Void {
	final fixture = CppResolvedFixture.load({sourceRoot: "test/fixtures/cpp_string_index_of_seed", mainModule: "Main", requiredModules: ["String"]});
	final program = CppResolvedFixture.prepare(fixture);
	final projection = new backend.cpp.CppTypedProgramProjection(program);
	final boundary = M14CppStringIndexOfBoundary.header(projection);
	final output = ".tmp/cpp-string-index-of";
	backend.cpp.CppTargetCore.emit(program, new backend.BackendContext(output, null, "Main", false, fixture.defines));
	projection.assertCurrent();
	sys.io.File.saveContent(output + "/IndexOfBoundary.hpp", boundary);
	CppManagedAssertionFixture.sanitizers(output, "CPP_STRING_INDEX_OF", "test/cpp_managed_heap/StringIndexOfObserver.cpp");
}
