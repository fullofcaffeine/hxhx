import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe selected catch values and authored returns through native execution. */
class M14SourceTryControlTest {
	public static function run():Void {
		final path = "test/oracle/source_try_control_seed/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		final context = new BackendContext(".tmp/source-try-control", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false), context);
		if (!result.builtExecutable)
			throw "source try requires a native executable";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "try lowering changed original typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent("test/oracle/source_try_control_seed/expected.stdout"))
			throw "try control or catch selection changed observed behavior: " + stdout + stderr;
		Sys.println("SOURCE_TRY_CONTROL_NATIVE:PASS");
	}

	static function main():Void
		run();
}
