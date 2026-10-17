import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Require the real exception provider to execute through the normal native target. */
class M14CppExceptionConstructionTest {
	static function main():Void {
		final root = "test/oracle/cpp_exception_construction_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: root, mainModule: "Main", requiredModules: ["haxe.Exception"]});
		final program = new MacroExpandedProgram(TypedAbstractOperatorLowering.lowerModules(fixture.modules, fixture.index), false);
		final result = CppTargetCore.emit(program, new BackendContext(".tmp/cpp-exception-construction", null, "Main", true, true, fixture.defines));
		if (!result.builtExecutable)
			throw "exception construction requires a native executable";
		final child = new sys.io.Process(result.entryPath, []);
		final stdout = child.stdout.readAll().toString();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "native exception construction differs: " + stdout + stderr;
		Sys.println("CPP_EXCEPTION_CONSTRUCTION:PASS");
	}
}
