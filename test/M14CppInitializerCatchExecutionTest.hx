/** Run authored field and nested-closure catches through the complete native program pipeline. */
class M14CppInitializerCatchExecutionTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/cpp_initializer_catch_storage_seed",
			mainModule: "Main",
			requiredModules: []
		});
		final context = new backend.BackendContext(".tmp/cpp-initializer-catch-execution", null, "Main", true, true, fixture.defines);
		final result = backend.cpp.CppTargetCore.emit(new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index),
			false), context);
		if (!result.builtExecutable)
			throw "initializer catches require a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "initializer catch execution differs from upstream: " + stdout + stderr;
		Sys.println("CPP_INITIALIZER_CATCH_EXECUTION:PASS");
	}

	static function main():Void
		run();
}
