import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Exercise authored do/while control inside value groups through native execution. */
class M14SourceDoWhileTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_do_while_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions) {
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "repeated do/while lowering changed control or local identities";
		}
		final context = new BackendContext(".tmp/source-do-while", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(new MacroExpandedProgram(fixture.modules, false), context);
		if (!result.builtExecutable)
			throw "do/while fixture requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "do/while lowering changed typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_do_while_seed/expected.stdout"))
			throw "do/while changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_DO_WHILE_NATIVE:PASS");
	}

	static function main():Void
		run();
}
