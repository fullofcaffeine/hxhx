import backend.BackendContext;
import backend.cpp.CppTargetCore;

/** Observe generic null comparisons through generated C++ and an actual process. */
class M14CppGenericNullComparisonIntegrationTest {
	public static function run():Void {
		final root = "test/oracle/cpp_generic_null_seed";
		final path = root + "/src/Main.hx";
		final resolved = new ResolvedModule("Main", path, ParserStage.parse(sys.io.File.getContent(path), path));
		final typed = TyperStage.typeResolvedModule(resolved, TyperIndex.build([resolved]));
		final program = new MacroExpandedProgram([typed], false);
		final context = new BackendContext(".tmp/cpp-generic-null", null, "Main", true, true, new haxe.ds.StringMap<String>());
		final result = CppTargetCore.emit(program, context);
		if (!result.builtExecutable)
			throw "Generic null comparisons require a native C++ executable";
		final process = new sys.io.Process(result.entryPath, []);
		final stdout = process.stdout.readAll().toString();
		final stderr = process.stderr.readAll().toString();
		final code = process.exitCode();
		process.close();
		if (code != 0 || stdout != sys.io.File.getContent(root + "/expected.stdout"))
			throw "Generic null comparison behavior differs: " + stdout + stderr;
		Sys.println("CPP_GENERIC_NULL_COMPARISON_NATIVE:PASS");
	}

	static function main():Void
		run();
}
