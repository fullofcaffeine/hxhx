import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Exercise an authored loop inside a value group through native execution. */
class M14SourceWhileValueTest {
	public static function run():Void {
		final fixture = CppResolvedFixture.load({sourceRoot: "test/oracle/source_while_value_seed/src", mainModule: "Main", requiredModules: ["Sys"]});
		final typed = fixture.main;
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final context = new BackendContext(".tmp/source-while-value", null, "Main", true, true, fixture.defines);
		final result = CppTargetCore.emit(new MacroExpandedProgram(fixture.modules, false), context);
		if (!result.builtExecutable)
			throw "while value fixture requires a native executable";
		for (i in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[i]) != revisions[i])
				throw "while lowering changed typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_while_value_seed/expected.stdout"))
			throw "while value changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_WHILE_VALUE_NATIVE:PASS");
	}

	static function main():Void
		run();
}
