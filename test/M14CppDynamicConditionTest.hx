import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Compare ordinary and guarded Dynamic conditions with the independent native C++ reference. */
class M14CppDynamicConditionTest {
	static function main():Void {
		final source = "test/oracle/cpp_dynamic_condition_seed";
		final fixture = CppResolvedFixture.load({sourceRoot: source, mainModule: "Main", requiredModules: ["Array", "Sys"]});
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture),
			new BackendContext(".tmp/cpp-dynamic-condition", null, "Main", true, fixture.defines));
		if (!result.builtExecutable)
			throw "Dynamic conditions require a native executable";
		final child = new sys.io.Process(result.entryPath, []);
		final stdout = child.stdout.readAll();
		final stderr = child.stderr.readAll().toString();
		final code = child.exitCode();
		child.close();
		if (code != 0 || stderr.length != 0 || stdout.compare(sys.io.File.getBytes(source + "/expected.stdout")) != 0)
			throw "native Dynamic conditions differ: exit=" + code + " stdout=" + stdout.toString() + " stderr=" + stderr;
		Sys.println("CPP_DYNAMIC_CONDITION_COMPLETE:PASS");
	}
}
