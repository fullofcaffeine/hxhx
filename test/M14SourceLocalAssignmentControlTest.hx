import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** A control-valued RHS writes its exact local only after normal completion. */
class M14SourceLocalAssignmentControlTest {
	public static function run():Void {
		runProgram("StatementMain", "statement.stdout");
		runProgram("Main", "expected.stdout");
		Sys.println("SOURCE_LOCAL_ASSIGNMENT_CONTROL:PASS");
	}

	/** Keep statement assignment evidence separate from the full parenthesized-value workload. */
	static function runProgram(name:String, expected:String):Void {
		final root = "test/oracle/source_local_assignment_control_seed";
		final path = root + "/src/" + name + ".hx";
		final resolved = new ResolvedModule(name, path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final functions = typed.getTypedClasses()[0].getFunctions();
		final revisions = [for (fn in functions) CompilerTypedTreeRevision.functionBody(fn)];
		for (fn in functions) {
			final lowered = TypedControlLowering.functionBody(fn);
			if (CompilerTypedTreeRevision.functionBody(lowered) != CompilerTypedTreeRevision.functionBody(TypedControlLowering.functionBody(lowered)))
				throw "repeated local assignment lowering changed its identities";
		}
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false),
			new BackendContext(".tmp/source-local-assignment-control/" + name, null, name, true, true, new haxe.ds.StringMap<String>()));
		if (!result.builtExecutable)
			throw "local assignment contract requires a native executable";
		for (index in 0...functions.length)
			if (CompilerTypedTreeRevision.functionBody(functions[index]) != revisions[index])
				throw "assignment lowering changed typed source";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/" + expected))
			throw "local assignment changed control or values: " + stdout + stderr;
		Sys.println("SOURCE_LOCAL_ASSIGNMENT_PROGRAM:PASS " + name);
	}

	static function main():Void
		run();
}
