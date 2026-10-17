/** Compare generic constructor storage with concrete native destinations and forced collection. */
class M14CppGenericAbstractStorageTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_generic_abstract_storage_seed", mainModule: "Main", requiredModules: []});
		final expanded = new MacroExpandedProgram(fixture.modules, false);
		final output = ".tmp/cpp-generic-abstract-storage";
		final result = backend.cpp.CppTargetCore.emit(expanded, new backend.BackendContext(output, null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable || Sys.command(result.entryPath, []) != 0)
			throw "generic abstract storage did not execute its native assertions";
		CppManagedAssertionFixture.sanitizers(output, "CPP_GENERIC_ABSTRACT_STORAGE");
		Sys.println("CPP_GENERIC_ABSTRACT_STORAGE:PASS");
	}
}
