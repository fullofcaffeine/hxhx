import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Prove that iteration in a capturing function returns from that exact function. */
class M14SourceForReturnTest {
	public static function run():Void {
		// The native ABI requires the real Array identity, including inside captures
		// and callback results. Resolve the same standard providers as an application.
		final fixture = CppResolvedFixture.load({
			sourceRoot: "test/oracle/source_for_return_seed/src",
			mainModule: "Main",
			requiredModules: ["Array", "Sys"]
		});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final context = new BackendContext(".tmp/source-for-return", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(new MacroExpandedProgram(fixture.modules, false), context);
		if (!result.builtExecutable)
			throw "source for requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "for lowering changed typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_for_return_seed/expected.stdout"))
			throw "for return changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_FOR_RETURN_NATIVE:PASS");
	}

	static function main():Void
		run();
}
