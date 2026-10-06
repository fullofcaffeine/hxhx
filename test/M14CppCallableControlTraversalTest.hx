import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** A lowered function body must remain visible to C++ callback argument analysis. */
class M14CppCallableControlTraversalTest {
	public static function run():Void {
		final root = "test/oracle/source_callable_control_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final context = new BackendContext(".tmp/source-callable-control", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(new MacroExpandedProgram([typed], false), context);
		if (!result.builtExecutable)
			throw "callback control traversal requires a native executable";
		final process = new sys.io.Process(result.entryPath, []);
		final output = process.stdout.readAll().toString();
		final errors = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || output != sys.io.File.getContent(root + "/expected.stdout"))
			throw "callback control traversal changed native behavior: " + output + errors;
		Sys.println("CPP_CALLABLE_CONTROL_TRAVERSAL:PASS");
	}

	static function main():Void
		run();
}
