import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Preserve the full original null-storage program with ordinary method loops. */
class M14CppRootLoopProgramTest {
	static function main():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/cpp_root_loop_seed/original", mainModule: "Main", requiredModules: ["Array"]});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = CppTargetCore.emit(program, new BackendContext(".tmp/cpp-root-loop-original", null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "original loop program requires native execution";
		final timeout = Sys.systemName() == "Mac" ? "gtimeout" : "timeout";
		final process = new sys.io.Process(timeout, ["60", result.entryPath]);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != "" || stderr != "")
			throw "original null-storage program failed: " + stdout + stderr;
		Sys.println("CPP_ROOT_LOOP_ORIGINAL:PASS");
	}
}
