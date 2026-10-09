import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe switch-arm loop exits and selected values through native execution. */
class M14SourceSwitchLoopTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_switch_loop_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions) {
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "repeated switch lowering changed the selected control structure";
		}
		final context = new BackendContext(".tmp/source-switch-loop", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(CppResolvedFixture.prepare(fixture), context);
		if (!result.builtExecutable)
			throw "source switch requires a native executable";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "switch lowering changed the original typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_switch_loop_seed/expected.stdout"))
			throw "switch-arm loop control changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_SWITCH_LOOP_NATIVE:PASS");
	}

	static function main():Void
		run();
}
